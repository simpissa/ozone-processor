`timescale 1ns / 1ps

module load_queue #(
    parameter LQ_SIZE = 8,
    parameter ID_W = 4,
    parameter AGE_W = 15
)(
    input  logic         clk,
    input  logic         reset,

    // Incoming trace operations
    input  logic         trace_valid,
    input  logic [2:0]   trace_op,
    input  logic [ID_W-1:0]   trace_id,
    input  logic [47:0]  trace_vaddr,
    input  logic         trace_vaddr_is_valid,
    input  logic [AGE_W-1:0] trace_age,
    output logic         trace_ready,

    // Interface to Store Queue (for dependency checking / forwarding)
    output logic         sq_query_valid,
    output logic [47:0]  sq_query_addr,
    output logic [3:0]   sq_query_id,
    output logic [AGE_W-1:0] sq_query_age,
    input  logic         sq_forward_valid, 
    input  logic [63:0]  sq_forward_data,
    input  logic         sq_conflict,
    input  logic         sq_miss,

    // information for store queue, but we don't really care
    output logic [AGE_W-1:0] lq_head_age,
    output logic             lq_head_valid,

    // Request to L1 data cache
    output logic         l1_req_valid,
    output logic [47:0]  l1_req_vaddr,
    output logic [3:0]   l1_req_id,
    input  logic         l1_req_ready,
    input  logic         l1_req_received,

    // Response from cache hierarchy
    input  logic         l1_resp_valid,
    input  logic [3:0]   l1_resp_id,
    input  logic [63:0]  l1_resp_data,

    // Completion output (load finished)
    output logic         load_complete_valid,
    output logic [3:0]   load_complete_id,
    output logic [63:0]  load_complete_data
);

localparam IDX_W = $clog2(LQ_SIZE);
localparam INVALID_IDX = LQ_SIZE;
localparam N_TRACES = 1 << ID_W;

typedef struct packed {
    logic valid;
    logic [ID_W-1:0] id;
    logic [AGE_W-1:0] age;
    logic [47:0] vaddr;
    logic addr_valid;
    logic issued;
    logic conflict;
    logic completed;
    logic [63:0] data;
} lq_entry;

typedef enum logic [2:0] {
    OP_MEM_LOAD    = 3'd0, // perform memory load
    OP_MEM_STORE   = 3'd1, // shouldn't need
    OP_MEM_RESOLVE = 3'd2, // resolve vaddr
    OP_TLB_FILL    = 3'd4  // shouldn't need
} op_code;

logic [IDX_W-1:0] head;
logic [IDX_W-1:0] tail;

logic [LQ_SIZE-1:0] ready;

// id map needs to have 
logic [IDX_W:0] id_map [0:N_TRACES-1];
lq_entry queue [0:LQ_SIZE-1];

assign lq_head_valid = queue[head].valid;
assign lq_head_age   = queue[head].age;

// misc logic
logic sq_had_miss;

// stages
logic waiting_issue;
logic issue_storeq;
logic issue_cache;

// used for logic finding which load we want to try and resolve
logic found_issue;
logic [IDX_W-1:0] next_issue_idx;
logic [IDX_W-1:0] issue_idx;

logic DBG;
logic [20:0] count;

assign trace_ready = !queue[tail].valid;

task print_queue;
    if (DBG) begin    
        $display("\nhead: %d, tail: %d", head, tail);
        for (int i = 0; i < LQ_SIZE; ++i) begin
            $display("entry %d: valid %d id %d addr 0x%012x addrvalid %d rdy %d issd %d conf %d cmpl %d",
                    i,
                    queue[i].valid,
                    queue[i].id,
                    queue[i].vaddr,
                    queue[i].addr_valid,
                    ready[i],
                    queue[i].issued,
                    queue[i].conflict,
                    queue[i].completed);
        end
        $display();
    end
endtask

/* initialize everything important to 0 */
initial begin

    if (!$value$plusargs("LQDEBUG=%b", DBG)) begin
        DBG = 0;
    end

    for (int i = 0; i < LQ_SIZE; ++i) begin
        queue[i].valid     = 0;
        queue[i].issued    = 0;
        queue[i].conflict  = 0;
        queue[i].completed = 0;
        id_map[i]          = INVALID_IDX;
    end

    head = 0;
    tail = 0;
    issue_storeq = 0;
    issue_cache = 0;
    waiting_issue = 1;
    sq_query_valid = 0;
    l1_req_valid = 0;
    load_complete_valid = 0;
    sq_had_miss = 0;
    count = 0;

end

always_ff @(posedge clk) begin

    count <= count + 1;

    // set our queue and ptrs back to 0
    if (reset) begin

        for (int i = 0; i < LQ_SIZE; ++i) begin
            queue[i].valid      <= 1'b0;
            queue[i].vaddr      <= 48'b0;
            queue[i].addr_valid <= 1'b0;
            queue[i].issued     <= 1'b0;
            queue[i].conflict   <= 1'b0;
            queue[i].completed  <= 1'b0;
            queue[i].data       <= 64'b0;
            id_map[i]           <= INVALID_IDX;
        end

        head <= 0;
        tail <= 0;
        issue_storeq  <= 0;
        issue_cache   <= 0;
        sq_had_miss <= 0;

        sq_query_valid <= 0;
        l1_req_valid <= 0;
        load_complete_valid <= 0;

        waiting_issue <= 1;
    end

    // new trace coming in! pick it up if necessary
    if (trace_valid) begin

        if (trace_op == OP_MEM_LOAD) begin
            if (DBG)
                $display("Loadq Status: Received Load trace.");
            // check if queue is full
            // if tail == head, then valid bit on queue head tells us if its full or empty
            // it SHOULD BE that the only case that the queue head isn't valid is when it's empty

            if (tail != head || !queue[head].valid) begin
                if (DBG)
                    $display("Loadq Status: Processing Load trace. %d", trace_id);

                assert(!queue[tail].valid);

                id_map[trace_id] <= { 1'b0, tail };

                queue[tail].id          <= trace_id;
                queue[tail].vaddr       <= trace_vaddr;
                queue[tail].addr_valid  <= trace_vaddr_is_valid;
                queue[tail].age         <= trace_age;
                queue[tail].issued      <= 0;
                queue[tail].conflict    <= 0;
                queue[tail].completed   <= 0;
                queue[tail].valid       <= 1;

                tail <= tail + 1;
            end

        end else if (trace_op == OP_MEM_RESOLVE) begin
            if (DBG)
                $display("Loadq Status: Received Resolve trace.");
            assert(trace_vaddr_is_valid);

            // do we actually have something for this trace_id, or is it just for a store?
            if (id_map[trace_id] != INVALID_IDX) begin
                assert(queue[id_map[trace_id][IDX_W-1:0]].valid);

                queue[id_map[trace_id][IDX_W-1:0]].vaddr       <= trace_vaddr;
                queue[id_map[trace_id][IDX_W-1:0]].addr_valid  <= trace_vaddr_is_valid;
            end

            // reset all conflict bits
            for (int i = 0; i < LQ_SIZE; ++i) begin
                queue[i].conflict <= 0;
            end
        end else begin
            if (DBG)
                $display("Loadq Status: Received trace to be ignored.");
        end
    end

    print_queue();

    if (waiting_issue) begin

        if (DBG) begin
            $display("Loadq Status: Awaiting issue and/or trace");
        end

        if (found_issue) begin
            if (DBG)
                $display("Loadq status: Issuing request to storeq");

            assert(queue[next_issue_idx].valid);
            assert(queue[next_issue_idx].addr_valid); // is this one necessary? i think so
            assert(!queue[next_issue_idx].issued);

            // we know what we want to try and resolve, so let's ask our store queue
            issue_storeq <= 1;

            sq_query_addr  <= queue[next_issue_idx].vaddr;
            sq_query_id    <= queue[next_issue_idx].id;
            sq_query_age   <= queue[next_issue_idx].age;
            sq_query_valid <= 1;
            
            // its in the issue pipeline now
            issue_idx <= next_issue_idx; // next is free to change now, which can most certainly happen while we're in issue
            queue[next_issue_idx].issued <= 1;
            waiting_issue <= 0;
        end
    end

    if (issue_storeq) begin
        if (sq_miss || sq_had_miss) begin
            sq_had_miss <= 1;
            if (DBG)
                $display("waiting to issue cache on id %d", queue[issue_idx].id);
            // no data to forward, so query the cache
            if (l1_req_ready) begin

                // don't care anymore
                sq_had_miss <= 0;

                l1_req_vaddr <= queue[issue_idx].vaddr; 
                l1_req_id    <= queue[issue_idx].id;
                l1_req_valid <= 1;
                issue_cache  <= 1;
                issue_storeq <= 0;
                if (DBG)
                    $display("Loadq Status: request sent to l1");
            end


        end else if (sq_forward_valid) begin
            queue[issue_idx].completed <= 1;
            queue[issue_idx].data <= sq_forward_data;
            issue_storeq <= 0;
            waiting_issue <= 1;
            sq_query_valid <= 0;

        end else if (sq_conflict) begin
            queue[issue_idx].conflict <= 1;
            queue[issue_idx].issued <= 0;
            issue_storeq <= 0;
            waiting_issue <= 1;
            sq_query_valid <= 0;

        end

        sq_query_valid <= 0;

    end

    if (issue_cache) begin
        // we issued to the cache, waiting for a response
        
        // turn off req valid, otherwise by way of l1's structure it will continuously take the same request
        // also, pretty sure there's a bug where if storeq is also valid at the same cycle, we get ignored
        // but have no way of knowing we were ignore

        if (l1_req_received) begin
            if (DBG)
                $display("Loadq Status: L1 received request");
            l1_req_valid <= 0;
        end

        if (l1_resp_valid) begin

            if (DBG)
                $display("Loadq Status: Received response from L1. queue id %d l1_id %d issue_idx %d id_map idx %d", queue[issue_idx].id, l1_resp_id, issue_idx, id_map[l1_resp_id]);

            assert(queue[issue_idx].id == l1_resp_id);


            queue[issue_idx].completed <= 1;
            queue[issue_idx].data <= l1_resp_data;

            issue_cache <= 0;
            waiting_issue <= 1;
            l1_req_valid <= 0;
        end
    end

    // dequeue the head
    if (queue[head].completed && queue[head].valid) begin
        assert(queue[head].valid);

        if (DBG)
            $display("Loadq Status: Dequeueing head");

        // invalidate the entry for this guy
        id_map[queue[head].id] <= INVALID_IDX;

        load_complete_id    <= queue[head].id;
        load_complete_data  <= queue[head].data;
        load_complete_valid <= 1;

        // TODO: do we need to wait for data to be read? or can we just move on
        // note^: if I ever need to change this, i should make it combinatorial
        // (the output stuff) and have an input bit for load_received
        // whenever load received, do everything below!
        queue[head].valid <= 0; 
        queue[head].id <= 0;
        queue[head].vaddr <= '0;
        queue[head].addr_valid <= 0;
        queue[head].issued <= 0;
        queue[head].conflict <= 0;
        queue[head].completed <= 0;
        head <= head + 1;

    end else begin
        
        load_complete_id <= 0;
        load_complete_data <= 0;
        load_complete_valid <= 0;
    end

end


// maintain ready list and the idx of which entry we should issue next when possible
always_comb begin
	int idx;
    for (int i = 0; i < LQ_SIZE; ++i) begin
        ready[i] = queue[i].valid && queue[i].addr_valid 
                && !queue[i].issued && !queue[i].conflict;
    end
    
    found_issue = 0;
    next_issue_idx = '0;

    for (int i = 0; i < LQ_SIZE; ++i) begin
        idx = (int'(head) + i) % LQ_SIZE;

        if (!found_issue && ready[idx]) begin
            found_issue = 1;
            next_issue_idx = idx[IDX_W-1:0];
        end
    end
end

endmodule

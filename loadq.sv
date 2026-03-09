
module load_queue #(
    parameter LQ_SIZE = 16,
    parameter ID_W = 4
)(
    input  logic         clk,
    input  logic         reset,

    // Incoming trace operations
    input  logic         trace_valid,
    input  logic [2:0]   trace_op,
    input  logic [ID_W-1:0]   trace_id,
    input  logic [47:0]  trace_vaddr,
    input  logic         trace_vaddr_is_valid,

    // Interface to Store Queue (for dependency checking / forwarding)
    output logic         sq_query_valid,
    output logic [47:0]  sq_query_addr,
    output logic [3:0]   sq_query_id,
    input  logic         sq_forward_valid,
    input  logic [63:0]  sq_forward_data,
    input  logic         sq_conflict,

    // need a way for sq to tell us that they didn't find it so we can query cache

    // Request to L1 data cache
    output logic         l1_req_valid,
    output logic [47:0]  l1_req_vaddr,
    output logic [3:0]   l1_req_id,
    input  logic         l1_req_ready,

    // Response from cache hierarchy
    input  logic         l1_resp_valid,
    input  logic [3:0]   l1_resp_id,
    input  logic [63:0]  l1_resp_data,

    // Completion output (load finished)
    output logic         load_complete_valid,
    output logic [3:0]   load_complete_id,
    output logic [63:0]  load_complete_data
);

// TODO: add "ROB idx" (count # of traces) to store relative age
typedef struct packed {
    logic valid;
    logic [ID_W-1:0] id;
    logic [47:0] vaddr;
    logic addr_valid;
    logic issued;
    logic completed;
    logic [63:0] data;
} lq_entry;

typedef enum logic [2:0] {
    OP_MEM_LOAD    = 0, // perform memory load
    OP_MEM_STORE   = 1, // shouldn't need
    OP_MEM_RESOLVE = 2, // resolve vaddr
    OP_TLB_FILL    = 4  // shouldn't need (unless we drive the tlb?)
} op_code;

localparam IDX_W = $clog2(LQ_SIZE);

logic [IDX_W-1:0] head;
logic [IDX_W-1:0] tail;

logic [LQ_SIZE-1:0] ready;
logic [ID_W-1:0] id_map [0:LQ_SIZE-1];
lq_entry queue [0:LQ_SIZE-1];

// stages
logic waiting_issue;
logic issue_storeq;
logic issue_cache;

// used for logic finding which load we want to try and resolve
logic found_issue;
logic [IDX_W-1:0] next_issue_idx;
logic [IDX_W-1:0] issue_idx;

/* initialize everything important to 0 */
initial begin
    for (int i = 0; i < LQ_SIZE; ++i) begin
        queue[i].valid = 0;
        id_map[i]      = 0;
    end

    head = 0;
    tail = 0;
    issue_storeq = 0;
    issue_cache = 0;

end


always_ff @(posedge clk) begin
    
    // set our queue and ptrs back to 0
    if (reset) begin

    for (int i = 0; i < LQ_SIZE; ++i) begin
        queue[i].valid      <= 1'b0;
        queue[i].vaddr      <= 48'b0;
        queue[i].addr_valid <= 1'b0;
        queue[i].issued     <= 1'b0;
        queue[i].completed  <= 1'b0;
        queue[i].data       <= 64'b0;
        id_map[i]           <= 0;
    end

    head <= 0;
    tail <= 0;
    issue_storeq <= 0;
    issue_cache  <= 0;

    end
    
    // new trace coming in! pick it up if necessary
    if (trace_valid) begin

        if (trace_op == OP_MEM_LOAD) begin
            assert(!queue[tail].valid);

            // this will need to be changed to make sure we have room to accept
            // will probably have to figure out a way to tell the trace issuer that we haven't collected
            // for now, whatever
            assert(tail != head); 

            id_map[trace_id] <= tail;

            queue[tail].id          <= trace_id;
            queue[tail].vaddr       <= trace_vaddr;
            queue[tail].addr_valid  <= trace_vaddr_is_valid;

            tail <= tail + 1;

        end else if (trace_op == OP_MEM_RESOLVE) begin
            assert(queue[id_map[trace_id]].valid);
            assert(trace_vaddr_is_valid);

            queue[id_map[trace_id]].vaddr       <= trace_vaddr;
            queue[id_map[trace_id]].addr_valid  <= trace_vaddr_is_valid;

        end

    end

    if (waiting_issue) begin
        
        if (found_issue) begin

            assert(queue[next_issue_idx].valid);
            assert(queue[next_issue_idx].addr_valid); // is this one necessary? i think so
            assert(!queue[next_issue_idx].issued);

            // we know what we want to try and resolve, so let's ask our store queue
            issue_storeq <= 1;

            sq_query_addr  <= queue[next_issue_idx].vaddr;
            sq_query_id    <= queue[next_issue_idx].id;
            sq_query_valid <= 1;
            
            // its in the issue pipeline now
            issue_idx <= next_issue_idx; // next is free to change now, which can most certainly happen while we're in issue
            queue[next_issue_idx].issued <= 1;
            waiting_issue <= 0;

        end

    end


    if (issue_storeq) begin
        // we issued to the storeq, waiting for a response

        // TODO: need to create an option for sq to tell us it wasn't there
        // so we can query the cache
        if (sq_forward_valid) begin
            queue[issue_idx].completed <= 1;
            queue[issue_idx].data <= sq_forward_data;
            issue_storeq <= 0;
            waiting_issue <= 1;
        end else if (sq_conflict) begin
            // TODO
        end

    end

    // TODO: create a stage where we wait to make sure the cache is free for a request

    if (issue_cache) begin
        // we issued to the cache, waiting for a response
        if (l1_resp_valid) begin
            assert(queue[issue_idx].id == l1_resp_id)

            queue[issue_idx].completed <= 1;
            queue[issue_idx].data <= l1_resp_data;

            issue_cache <= 0;
            waiting_issue <= 1;
        end
    end
    

    // dequeue the head
    if (queue[head].completed) begin
        load_complete_id <= queue[head].id;
        load_complete_data <= queue[head].data;
        load_complete_valid <= 1;

        // TODO: do we need to wait for data to be read? or can we just move on
        head <= head + 1;
    end else begin
        load_complete_id <= 0;
        load_complete_data <= 0;
        load_complete_valid <= 0;
    end

end


// maintain ready list and the idx of which entry we should issue next when possible
always_comb begin
    for (int i = 0; i < LQ_SIZE; ++i) begin
        ready[i] = queue[i].valid && queue[i].addr_valid && !queue[i].issued;
    end

    found_issue = 0;
    next_issue_idx = '0;

    for (int i = 0; i < LQ_SIZE; ++i) begin
        int idx = (32'(head) + i) % LQ_SIZE;

        if (!found_issue && ready[idx]) begin
            found_issue = 1;
            next_issue_idx = idx[IDX_W-1:0];
        end
    end
end

endmodule

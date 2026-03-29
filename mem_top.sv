`timescale 1ns / 1ps

module mem_top #(
    parameter int PAGE_OFF_W = 12,
    parameter int VADDR_W = 48,
    parameter int PADDR_W = 30,
    parameter int TLB_ENTRIES = 16,
    parameter int ID_W = 4,
    parameter int AGE_W = 15,
    parameter int LQ_SIZE = 8,
    parameter int SQ_SIZE = 8
) (
    input logic clk,
    input logic rst,

    // raw trace from HPS
    input logic trace_valid,
    output logic trace_ready,
    input logic [127:0] trace_data,
    
    // TODO: i think this is unnecessary, since l2 is what stores writes
    // these inputs need to instead be used to interact with l1
    // yea i originally thought this was needed for grading but nate prob has his own way of looking at architectural state
    /*
    // store commits, send to HPS
    input logic commit_ready,
    output logic commit_valid,
    output logic [VADDR_W-1:0] commit_vaddr,
    output logic [63:0] commit_value,
    */
    
    // TODO: It's just my interpretation, but I think these need to be internal
    // and the avm_m0 inputs are what need to be here
    // so I'll do that
    
    output logic avm_m0_read,
    output logic avm_m0_write,
    output logic [255:0] avm_m0_writedata,
    output logic [31:0] avm_m0_address,
    input logic [255:0] avm_m0_readdata,
    input logic avm_m0_readdatavalid,
    output logic [31:0] avm_m0_byteenable,
    input logic avm_m0_waitrequest,
    output logic [10:0] avm_m0_burstcount

    /*
    // sdram interface with l2
    output logic         sdram_req_valid,
    input  logic         sdram_req_ready,
    output logic         sdram_req_rw,
    output logic [31:0]  sdram_req_addr,
    output logic [511:0] sdram_req_wdata,
    input  logic         sdram_resp_valid,
    input  logic [511:0] sdram_resp_rdata
    */

);

    typedef enum logic [2:0] {
        OP_MEM_LOAD    = 0,
        OP_MEM_STORE   = 1,
        OP_MEM_RESOLVE = 2,
        OP_TLB_FILL    = 4
    } op_code;

    // latched trace data — decouples trace_ready from trace_data contents
    logic [127:0] trace_data_r;
    logic trace_pending;
    logic downstream_ready;

    logic [2:0] trace_op;
    logic [ID_W-1:0] trace_id;
    logic [VADDR_W-1:0] trace_vaddr;
    logic trace_vaddr_is_valid;
    logic trace_value_is_valid;
    logic [63:0] trace_value;
    logic [PADDR_W-1:0] trace_tlb_paddr;

    logic trace_fire;
    logic [AGE_W-1:0] access_age;

    logic lq_trace_ready;
    logic lq_trace_valid;
    logic [AGE_W-1:0] lq_trace_age;

    logic sq_trace_valid;
    logic sq_ready_out;
    logic sq_resolve;
    logic [AGE_W-1:0] sq_age;
    logic [VADDR_W-1:0] sq_search_addr;
    logic [AGE_W-1:0] sq_load_age;
    logic sq_found;
    logic sq_resolved;
    logic [63:0] sq_search_value;

    logic lq_sq_query_valid;
    logic [VADDR_W-1:0] lq_sq_query_addr;
    logic [ID_W-1:0] lq_sq_query_id;
    logic [AGE_W-1:0] lq_sq_query_age;
    logic lq_sq_forward_valid;
    logic [63:0] lq_sq_forward_data;
    logic lq_sq_conflict;
    logic lq_sq_miss;
    logic [AGE_W-1:0] lq_head_age; 
    logic lq_head_valid;

    logic l1_req_valid;
    logic [VADDR_W-1:0] l1_req_vaddr;
    logic [ID_W-1:0] l1_req_id;
    logic l1_req_ready;
    logic l1_resp_valid;
    logic [ID_W-1:0] l1_resp_id;
    logic [63:0] l1_resp_data;
    logic l1_lq_req_received;

    logic tlb_lookup_valid;
    logic [VADDR_W-1:0] tlb_lookup_vaddr;
    logic tlb_resp_valid;
    logic [PADDR_W-1:0] tlb_resp_paddr;
    logic [511:0] l2_resp_data;

    logic tlb_fill_valid;
    logic tlb_fill_ready;

    logic raw_trace_is_resolve;

    // accept a new trace from HPS whenever we aren't already holding one
    assign trace_ready = ~trace_pending;

    // latch incoming trace data on acceptance
    always_ff @(posedge clk) begin
        if (rst) begin
            trace_data_r <= '0;
            trace_pending <= 1'b0;
        end else begin
            if (trace_valid && trace_ready) begin
                trace_data_r <= trace_data;
                trace_pending <= 1'b1;
            end else if (trace_fire) begin
                trace_pending <= 1'b0;
            end
        end
    end

    // decode from latched data, not live trace_data
    assign trace_op = trace_data_r[54:52];
    assign trace_id = trace_data_r[51:48];
    assign trace_vaddr = trace_data_r[47:0];
    assign trace_vaddr_is_valid = trace_data_r[55];
    assign trace_value_is_valid = trace_data_r[120];
    assign trace_value = trace_data_r[119:56];
    assign trace_tlb_paddr = trace_data_r[85:56];

    // check if the downstream module for the latched op is ready
    always_comb begin
        case (trace_op)
            OP_MEM_LOAD: downstream_ready = lq_trace_ready;
            OP_MEM_STORE: downstream_ready = sq_ready_out;
            OP_MEM_RESOLVE: downstream_ready = 1'b1;
            OP_TLB_FILL: downstream_ready = tlb_fill_ready;
            default: downstream_ready = 1'b1;
        endcase
    end

    // dispatch the latched trace when downstream can accept
    assign trace_fire = trace_pending && downstream_ready;

    assign raw_trace_is_resolve = trace_pending && (trace_op == OP_MEM_RESOLVE);
    assign sq_search_addr = lq_sq_query_addr;
    assign sq_load_age = lq_sq_query_age;

    always_ff @(posedge clk) begin
        if (rst) begin
            access_age <= '0;
        end else if (trace_fire && ((trace_op == OP_MEM_LOAD) || (trace_op == OP_MEM_STORE))) begin
            access_age <= access_age + 1'b1;
        end
    end

    // set valids
    always_comb begin
        lq_trace_valid = 1'b0;
        lq_trace_age = access_age;

        sq_trace_valid = 1'b0;
        sq_resolve = raw_trace_is_resolve;
        sq_age = access_age;

        tlb_fill_valid = 1'b0;

        if (trace_fire) begin
            case (trace_op)
                OP_MEM_LOAD: lq_trace_valid = 1'b1;
                OP_MEM_STORE: sq_trace_valid = 1'b1;
                OP_MEM_RESOLVE: begin
                    if (trace_vaddr_is_valid) begin
                        lq_trace_valid = 1'b1;
                    end
                    sq_trace_valid = 1'b1;
                end
                OP_TLB_FILL: tlb_fill_valid = 1'b1;
                default: begin end
            endcase
        end
    end

    always_comb begin
        lq_sq_forward_valid = 1'b0;
        lq_sq_forward_data = sq_search_value;
        lq_sq_conflict = 1'b0;
        lq_sq_miss = 1'b0;

        if (lq_sq_query_valid) begin
            if (sq_found) begin
                if (sq_resolved) begin
                    lq_sq_forward_valid = 1'b1;
                end else begin
                    lq_sq_conflict = 1'b1;
                end
            end else begin
                lq_sq_miss = 1'b1;
            end
        end
    end

    load_queue #(
        .LQ_SIZE(LQ_SIZE),
        .ID_W(ID_W)
    ) lq (
        .clk(clk),
        .reset(rst),
        .trace_ready(lq_trace_ready),
        .trace_valid(lq_trace_valid),
        .trace_op(trace_op),
        .trace_id(trace_id),
        .trace_vaddr(trace_vaddr),
        .trace_vaddr_is_valid(trace_vaddr_is_valid),
        .trace_age(lq_trace_age),
        .sq_query_valid(lq_sq_query_valid),
        .sq_query_addr(lq_sq_query_addr),
        .sq_query_id(lq_sq_query_id), // TODO: currently unused, i think the sq should take this as input?
        .sq_query_age(lq_sq_query_age),
        .sq_forward_valid(lq_sq_forward_valid),
        .sq_forward_data(lq_sq_forward_data),
        .sq_conflict(lq_sq_conflict),
        .sq_miss(lq_sq_miss),
        .lq_head_age(lq_head_age),
        .lq_head_valid(lq_head_valid),
        .l1_req_valid(l1_req_valid),
        .l1_req_vaddr(l1_req_vaddr),
        .l1_req_id(l1_req_id),
        .l1_req_ready(l1_req_ready),
        .l1_req_received(l1_lq_req_received),
        .l1_resp_valid(l1_resp_valid),
        .l1_resp_id(l1_resp_id),
        .l1_resp_data(l1_resp_data),
        .load_complete_valid(), // TODO: should these be used?
        .load_complete_id(),
        .load_complete_data()
    );

    logic [47:0] l1_write_vaddr;
    logic [63:0] l1_write_value;
    logic l1_valid_out;


    store_queue #(
        .SQ_SIZE(SQ_SIZE)
    ) sq (
        .rst(rst),
        .clk_in(clk),
        .valid_trace(sq_trace_valid),
        .ready_out(sq_ready_out),
        .trace_id(trace_id),
        .trace_vaddr(trace_vaddr),
        .trace_vaddr_is_valid(trace_vaddr_is_valid),
        .trace_value_is_valid(trace_value_is_valid),
        .trace_value(trace_value),
        .resolve(sq_resolve),
        .age(sq_age),
        .lq_head_age(lq_head_age),
        .lq_head_valid(lq_head_valid),
        .search_addr(sq_search_addr),
        .load_age(sq_load_age),
        .found(sq_found),
        .resolved(sq_resolved),
        .search_value(sq_search_value),
        .write_vaddr(l1_write_vaddr),
        .write_value(l1_write_value),
        .ready_in(l1_req_ready),
        .valid_out(l1_valid_out)
    );

    tlb #(
        .PAGE_OFF_W(PAGE_OFF_W),
        .VADDR_W(VADDR_W),
        .PADDR_W(PADDR_W),
        .ENTRIES(TLB_ENTRIES),
        .ID_W(ID_W)
    ) shared_tlb (
        .clk(clk),
        .rst(rst),
        .lookup_valid(tlb_lookup_valid),
        .lookup_vaddr(tlb_lookup_vaddr),
        .lookup_id('0),
        .lookup_ready(),
        .resp_valid(tlb_resp_valid),
        .resp_id(),
        .resp_hit(),
        .resp_paddr(tlb_resp_paddr),
        .fill_valid(tlb_fill_valid),
        .trace_op(trace_op),
        .fill_vaddr(trace_vaddr),
        .fill_paddr(trace_tlb_paddr),
        .fill_ready(tlb_fill_ready)
    );

    logic l2_req_valid;
    logic l2_req_rw;
    logic [23:0] l2_req_paddr;
    logic [511:0] l2_req_data;
    logic [ID_W-1:0] l2_query_id;
    logic [511:0] l2_evict_data;
    logic l2_evict_valid;
    logic l2_ready_for_req;
    logic l2_resp_valid;
    logic [23:0] l2_paddr;
    logic [ID_W-1:0] l2_resp_id;

    // TODO: lq-l1, sq-l1, l1-l2 communication are mismatched
    l1cache #( 
    .VADDR_W(VADDR_W),
    .PADDR_W(PADDR_W)
    ) l1 (
        .clk(clk),
        .reset(rst),
        .store_vaddr(l1_write_vaddr),
        .store_id(), // TODO: this one might be necessary?
        .storeValid(l1_valid_out),
        .store_data(l1_write_value),
        .store_received(),
        .store_id_completed(),
        .store_finished(),
        .loadValid(l1_req_valid),
        .load_vaddr(l1_req_vaddr),
        .load_id(l1_req_id),
        .load_received(l1_lq_req_received),
        .load_finished(l1_resp_valid),
        .load_id_completed(l1_resp_id),
        .data_out(l1_resp_data),
        .data_valid(l1_resp_valid),
        .l1ready(l1_req_ready),
        .l2_req_valid(l2_req_valid),
        .l2_req_rw(l2_req_rw),
        .l2_req_paddr(l2_req_paddr),
        .l2_req_data(l2_req_data),
        .l2_query_id(l2_query_id),
        .l2_evict_data(l2_evict_data), // TODO unused
        .l2_evict_valid(l2_evict_valid), // TODO unused
        .l2_ready_for_req(l2_ready_for_req),
        .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),
        .l2_paddr(l2_paddr),
        .l2_resp_id(l2_resp_id),
        .tlb_paddr_in(tlb_resp_paddr),
        .tlb_paddr_ready(tlb_resp_valid),
        .tlb_vaddr_out(tlb_lookup_vaddr),
        .tlb_vaddr_valid(tlb_lookup_valid)
    );

    // sdram interface with l2
    logic         sdram_req_valid;
    logic         sdram_req_ready;
    logic         sdram_req_rw;
    logic [31:0]  sdram_req_addr;
    logic [511:0] sdram_req_wdata;
    logic         sdram_resp_valid;
    logic [511:0] sdram_resp_rdata;

    l2cache l2 (
        .clk(clk),
        .rst(rst),
        .l1_req_valid(l2_req_valid),
        .l1_req_rw(l2_req_rw),
        .l1_req_paddr(l2_req_paddr),
        .l1_req_data(l2_req_data),
        .l1_query_id(l2_query_id),
        .l1_ready_for_input(l2_ready_for_req),
        .l1_resp_valid(l2_resp_valid),
        .l1_resp_data(l2_resp_data),
        .l1_output_id(l2_resp_id),
        .sdram_req_valid(sdram_req_valid),
        .sdram_req_ready(sdram_req_ready),
        .sdram_req_rw(sdram_req_rw),
        .sdram_req_addr(sdram_req_addr),
        .sdram_req_wdata(sdram_req_wdata),
        .sdram_resp_valid(sdram_resp_valid),
        .sdram_resp_rdata(sdram_resp_rdata)
    );

    sdram ram (
       .clk(clk),
       .reset(rst),
       .req_valid(sdram_req_valid),
       .req_ready(sdram_req_ready),
       .req_rw(sdram_req_rw),
       .req_addr(sdram_req_addr),
       .req_wdata(sdram_req_wdata),
       .resp_valid(sdram_resp_valid),
       .resp_rdata(sdram_resp_rdata),

        // TODO: is this done correctly?
       .avm_m0_read(avm_m0_read),
       .avm_m0_write(avm_m0_write),
       .avm_m0_writedata(avm_m0_writedata),
       .avm_m0_address(avm_m0_address),
       .avm_m0_readdata(avm_m0_readdata),
       .avm_m0_readdatavalid(avm_m0_readdatavalid),
       .avm_m0_byteenable(avm_m0_byteenable),
       .avm_m0_waitrequest(avm_m0_waitrequest),
       .avm_m0_burstcount(avm_m0_burstcount)
   );

endmodule

`timescale 1ns / 1ps

module trace_dispatch #(
    parameter int VADDR_W = 48,
    parameter int PADDR_W = 30,
    parameter int ID_W = 4,
    parameter int LQ_SIZE = 8,
    parameter int SQ_SIZE = 8
) (
    input logic clk,
    input logic rst,

    // raw trace from HPS
    input logic trace_valid,
    output logic trace_ready,
    input logic [2:0] trace_op,
    input logic [ID_W-1:0] trace_id,
    input logic [VADDR_W-1:0] trace_vaddr,
    input logic trace_vaddr_is_valid,
    input logic trace_value_is_valid,
    input logic [63:0] trace_value,
    input logic [PADDR_W-1:0] trace_tlb_paddr,

    // load queue
    output logic l1_req_valid,
    output logic [VADDR_W-1:0] l1_req_vaddr,
    output logic [ID_W-1:0] l1_req_id,
    input logic l1_req_ready,
    input logic l1_resp_valid,
    input logic [ID_W-1:0] l1_resp_id,
    input logic [63:0] l1_resp_data,

    // load queue completion
    output logic load_complete_valid,
    output logic [ID_W-1:0] load_complete_id,
    output logic [63:0] load_complete_data,

    // store commits, send to HPS
    input logic commit_ready,
    output logic commit_valid,
    output logic [VADDR_W-1:0] commit_vaddr,
    output logic [63:0] commit_value,

    // tlb fill stream, wired into shared tlb with l1
    output logic tlb_fill_valid,
    output logic [VADDR_W-1:0] tlb_fill_vaddr,
    output logic [PADDR_W-1:0] tlb_fill_paddr,
    input logic tlb_fill_ready
);

    typedef enum logic [2:0] {
        OP_MEM_LOAD    = 0,
        OP_MEM_STORE   = 1,
        OP_MEM_RESOLVE = 2,
        OP_TLB_FILL    = 4
    } op_code;

    localparam int AGE_W = ID_W + 1;

    // TODO: I think loadq should have a ready signal too? in the case that it stalls

    //       Also looks like an error in storeq, uses search_vaddr instead of search_addr

    //       We might need another module higher up to connect l1 and tlb

    logic trace_fire;
    logic [AGE_W-1:0] access_age;

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

    logic raw_trace_is_resolve;

    assign raw_trace_is_resolve = trace_valid && (trace_op == OP_MEM_RESOLVE);
    assign sq_search_addr = lq_sq_query_addr;
    assign sq_load_age = lq_sq_query_age;

    always_comb begin
        case (trace_op)
            OP_MEM_LOAD: trace_ready = 1'b1;
            OP_MEM_STORE: trace_ready = sq_ready_out;
            OP_MEM_RESOLVE: trace_ready = 1'b1;
            OP_TLB_FILL: trace_ready = tlb_fill_ready;
            default: trace_ready = 1'b1;
        endcase
    end

    assign trace_fire = trace_valid && trace_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            access_age <= '0;
        end else if (trace_fire && ((trace_op == OP_MEM_LOAD) || (trace_op == OP_MEM_STORE))) begin
            access_age <= access_age + 1'b1;
        end
    end

    always_comb begin
        lq_trace_valid = 1'b0;
        lq_trace_age = access_age;

        sq_trace_valid = 1'b0;
        sq_resolve = raw_trace_is_resolve;
        sq_age = access_age;

        tlb_fill_valid = 1'b0;
        tlb_fill_vaddr = trace_vaddr;
        tlb_fill_paddr = trace_tlb_paddr;

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

    // lq and sq communication, not sure if im doing this right
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
        .trace_valid(lq_trace_valid),
        .trace_op(trace_op),
        .trace_id(trace_id),
        .trace_vaddr(trace_vaddr),
        .trace_vaddr_is_valid(trace_vaddr_is_valid),
        .trace_age(lq_trace_age),
        .sq_query_valid(lq_sq_query_valid),
        .sq_query_addr(lq_sq_query_addr),
        .sq_query_id(lq_sq_query_id),
        .sq_query_age(lq_sq_query_age),
        .sq_forward_valid(lq_sq_forward_valid),
        .sq_forward_data(lq_sq_forward_data),
        .sq_conflict(lq_sq_conflict),
        .sq_miss(lq_sq_miss),
        .l1_req_valid(l1_req_valid),
        .l1_req_vaddr(l1_req_vaddr),
        .l1_req_id(l1_req_id),
        .l1_req_ready(l1_req_ready),
        .l1_resp_valid(l1_resp_valid),
        .l1_resp_id(l1_resp_id),
        .l1_resp_data(l1_resp_data),
        .load_complete_valid(load_complete_valid),
        .load_complete_id(load_complete_id),
        .load_complete_data(load_complete_data)
    );

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
        .search_addr(sq_search_addr),
        .load_age(sq_load_age),
        .found(sq_found),
        .resolved(sq_resolved),
        .search_value(sq_search_value),
        .write_vaddr(commit_vaddr),
        .write_value(commit_value),
        .ready_in(commit_ready),
        .valid_out(commit_valid)
    );

endmodule

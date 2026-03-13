`timescale 1ns / 1ps

module mem_top #(
    parameter int PAGE_OFF_W = 12,
    parameter int VADDR_W = 48,
    parameter int PADDR_W = 30,
    parameter int TLB_ENTRIES = 16,
    parameter int ID_W = 4,
    parameter int LQ_SIZE = 8,
    parameter int SQ_SIZE = 8
) (
    input logic clk,
    input logic rst,

    // raw trace from HPS
    input logic trace_valid,
    output logic trace_ready,
    input logic [127:0] trace_data,

    // store commits, send to HPS
    input logic commit_ready,
    output logic commit_valid,
    output logic [VADDR_W-1:0] commit_vaddr,
    output logic [63:0] commit_value
);

    typedef enum logic [2:0] {
        OP_MEM_LOAD    = 0,
        OP_MEM_STORE   = 1,
        OP_MEM_RESOLVE = 2,
        OP_TLB_FILL    = 4
    } op_code;

    localparam int AGE_W = ID_W + 1;

    logic [2:0] trace_op;
    logic [ID_W-1:0] trace_id;
    logic [VADDR_W-1:0] trace_vaddr;
    logic trace_vaddr_is_valid;
    logic trace_value_is_valid;
    logic [63:0] trace_value;
    logic [PADDR_W-1:0] trace_tlb_paddr;

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

    logic l1_req_valid;
    logic [VADDR_W-1:0] l1_req_vaddr;
    logic [ID_W-1:0] l1_req_id;
    logic l1_req_ready;
    logic l1_resp_valid;
    logic [ID_W-1:0] l1_resp_id;
    logic [63:0] l1_resp_data;

    logic tlb_lookup_valid;
    logic [VADDR_W-1:0] tlb_lookup_vaddr;
    logic tlb_resp_valid;
    logic [PADDR_W-1:0] tlb_resp_paddr;
    logic [511:0] l2_resp_data;

    logic tlb_fill_valid;
    logic tlb_fill_ready;

    logic raw_trace_is_resolve;

    assign trace_op = trace_data[54:52];
    assign trace_id = trace_data[51:48];
    assign trace_vaddr = trace_data[47:0];
    assign trace_vaddr_is_valid = trace_data[55];
    assign trace_value_is_valid = trace_data[120];
    assign trace_value = trace_data[119:56];
    assign trace_tlb_paddr = trace_data[85:56];

    assign raw_trace_is_resolve = trace_valid && (trace_op == OP_MEM_RESOLVE);
    assign sq_search_addr = lq_sq_query_addr;
    assign sq_load_age = lq_sq_query_age;

    // TODO: add load queue ready
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

    assign l1_req_ready = 1'b0;
    assign l1_resp_valid = 1'b0;
    assign l1_resp_id = '0;
    assign l1_resp_data = '0;

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
        .load_complete_valid(), // TODO: should these be used?
        .load_complete_id(),
        .load_complete_data()
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
        .lookup_id(),
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

    // TODO: lq-l1, sq-l1, l1-l2 communication are mismatched
    l1cache #( 
    .VADDR_W(VADDR_W),
    .PADDR_W(PADDR_W)
    ) l1 (
        .clk(clk),
        .reset(rst),
        .v_addr(l1_req_vaddr),
        .loadValid(l1_req_valid),
        .storeValid(commit_valid),
        .l1ready(),
        .miss(),
        .data_out(),
        .l2_data_in(l2_resp_data),
        .tlb_paddr_in(tlb_resp_paddr),
        .tlb_paddr_ready(tlb_resp_valid),
        .tlb_vaddr_out(tlb_lookup_vaddr),
        .tlb_vaddr_valid(tlb_lookup_valid)
    );

    l2cache l2 (
        .clk_in(clk),
        .l1_req_valid(),
        .l1_req_rw(),
        .l1_req_paddr(),
        .l1_req_data(),
        .l1_resp_valid(),
        .l1_resp_data(l2_resp_data)
    );

endmodule

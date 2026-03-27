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

    // I think the best way to do dram is to take as an input to mem_top?
    // That way it should get set in the fpga memory as the addr at 0x20000000 or whatever it is
    // can else test it easily by creating this segment 
    // this can just get plugged into the l2
    // input logic [63:] dram [0:1<<20],

    // raw trace from HPS
    input logic trace_valid,
    output logic trace_ready,
    input logic [127:0] trace_data,

    // store commits, send to HPS
    input logic commit_ready,
    output logic commit_valid,
    output logic [VADDR_W-1:0] commit_vaddr,
    output logic [63:0] commit_value,

    // sdram interface with l2
    output logic         sdram_req_valid,
    input  logic         sdram_req_ready,
    output logic         sdram_req_rw,
    output logic [31:0]  sdram_req_addr,
    output logic [511:0] sdram_req_wdata,
    input  logic         sdram_resp_valid,
    input  logic [511:0] sdram_resp_rdata
);

    typedef enum logic [2:0] {
        OP_MEM_LOAD    = 0,
        OP_MEM_STORE   = 1,
        OP_MEM_RESOLVE = 2,
        OP_TLB_FILL    = 4
    } op_code;

    localparam int AGE_W = ID_W + 1;

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

    logic l1_req_valid;
    logic [VADDR_W-1:0] l1_req_vaddr;
    logic [ID_W-1:0] l1_req_id;
    logic l1_req_ready;
    logic l1_resp_valid;
    logic [ID_W-1:0] l1_resp_id;
    logic [63:0] l1_resp_data;
    logic l1_load_nack;
    logic l1_store_nack;
    logic sq_l1_valid;
    logic [VADDR_W-1:0] sq_l1_vaddr;
    logic [63:0] sq_l1_value;
    logic [ID_W-1:0] sq_l1_id;
    logic sq_l1_ready;
    logic l1_store_finished;
    logic [ID_W-1:0] l1_store_id;
    logic l1_core_ready;
    logic l1_issue_load;
    logic l1_issue_store;

    logic tlb_lookup_valid;
    logic [VADDR_W-1:0] tlb_lookup_vaddr;
    logic tlb_resp_valid;
    logic tlb_resp_hit;
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
    assign commit_valid = 1'b0;
    assign commit_vaddr = '0;
    assign commit_value = '0;
    assign l1_issue_store = sq_l1_valid;
    assign l1_issue_load = l1_req_valid & ~l1_issue_store;
    assign sq_l1_ready = l1_issue_store & l1_core_ready;
    assign l1_req_ready = l1_issue_load & l1_core_ready;

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
        .l1_req_valid(l1_req_valid),
        .l1_req_vaddr(l1_req_vaddr),
        .l1_req_id(l1_req_id),
        .l1_req_ready(l1_req_ready),
        .l1_resp_valid(l1_resp_valid),
        .l1_resp_id(l1_resp_id),
        .l1_resp_data(l1_resp_data),
        .l1_nack(l1_load_nack),
        .tlb_fill(tlb_fill_valid),
        .load_complete_valid(), // TODO: should these be used? ans: i think so but am less confident, this is how we know the lq is putting out valid data from a load
                                // right, these 3 would be used normally, but I think for this assignment only stores need to be communicated to the HPS, lmk if im misunderstanding

                                // based on the trace logs, the loads have some sort of value associated with them, but im not sure what the purpose is. but i assume there has to be
                                // some way to test if loads are working? 
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
        .write_vaddr(sq_l1_vaddr),
        .write_value(sq_l1_value),
        .write_id(sq_l1_id),
        .ready_in(sq_l1_ready),
        .nack_in(l1_store_nack),
        .finished_in(l1_store_finished),
        .tlb_fill(tlb_fill_valid),
        .valid_out(sq_l1_valid)
    );

    tlb #(
        .PAGE_OFF_W(PAGE_OFF_W),
        .VADDR_W(VADDR_W),
        .PADDR_W(PADDR_W),
        .ENTRIES(TLB_ENTRIES),
        .ID_W(ID_W)
    ) tlb (
        .clk(clk),
        .rst(rst),
        .lookup_valid(tlb_lookup_valid),
        .lookup_vaddr(tlb_lookup_vaddr),
        .lookup_id(),
        .lookup_ready(),
        .resp_valid(tlb_resp_valid),
        .resp_id(),
        .resp_hit(tlb_resp_hit),
        .resp_paddr(tlb_resp_paddr),
        .fill_valid(tlb_fill_valid),
        .trace_op(trace_op),
        .fill_vaddr(trace_vaddr),
        .fill_paddr(trace_tlb_paddr),
        .fill_ready(tlb_fill_ready)
    );

    // TODO: sq-l1, l1-l2 communication are mismatched
    l1cache #(
    .VADDR_W(VADDR_W),
    .PADDR_W(PADDR_W)
    ) l1 (
        .clk(clk),
        .reset(rst),
        .load_vaddr(l1_req_vaddr),
        .store_vaddr(sq_l1_vaddr),
        .loadValid(l1_issue_load),
        .load_id(l1_req_id),
        .storeValid(l1_issue_store),
        .store_data(sq_l1_value),
        .store_id(sq_l1_id),
        .load_id_completed(l1_resp_id),
        .store_id_completed(l1_store_id),
        .store_finished(l1_store_finished),
        .load_finished(l1_resp_valid),
        .l1ready(l1_core_ready),
        .data_out(l1_resp_data),
        .data_valid(),
        .l2_req_valid(),
        .l2_req_rw(),
        .l2_req_paddr(),
        .l2_req_data(),
        .l2_query_id(),
        .l2_evict_data(),
        .l2_evict_valid(),
        .l2_ready_for_resp(1'b0),
        .l2_resp_valid(1'b0),
        .l2_resp_data('0),
        .l2_paddr('0),
        .l2_resp_id('0),
        // tlb
        .tlb_paddr_in(tlb_resp_paddr),
        .tlb_paddr_ready(tlb_resp_valid),
        .tlb_paddr_hit(tlb_resp_hit),
        .tlb_vaddr_out(tlb_lookup_vaddr),
        .tlb_vaddr_valid(tlb_lookup_valid),
        // nack on TLB miss
        .load_nack(l1_load_nack),
        .store_nack(l1_store_nack)
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

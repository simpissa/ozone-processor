`timescale 1ns / 1ps

module fetch (
    input logic clk,
    input logic reset,
    input logic flush,
    input logic [63:0] reset_pc_i,
    input logic [63:0] exe_target_i,

    // decode
    input logic         dcode_ready_i,
    output logic [31:0] dcode_instr_o,
    output logic [63:0] dcode_pc_o,
    output logic        dcode_pred_taken_o,
    output logic [63:0] dcode_pred_target_o,
    output logic        dcode_valid_o,

    // backend
    input logic [511:0] imem_rdata_i,
    input logic         imem_ready_i,
    input logic         imem_valid_i,
    output logic        imem_valid_o,
    output logic [29:0] imem_addr_o,

    // iTLB
    input logic         itlb_ready_i,
    input logic         itlb_hit_i,
    input logic [29:0]  itlb_paddr_i,
    input logic         itlb_miss_i,
    output logic [63:0] itlb_vaddr_o,
    output logic        itlb_valid_o,

    // branch predictor
    input logic         bp_taken_i,
    input logic [63:0]  bp_target_i,
    output logic        bp_valid_o,
    output logic [63:0] bp_vaddr_o
);

    typedef enum logic [1:0] {
        S_TLB_REQ,
        S_TLB_WAIT,
        S_IMEM_WAIT,
        S_OUT
    } fetch_state_t;

    fetch_state_t state;
    logic [63:0] pc;
    logic [63:0] req_pc;
    logic [29:0] req_paddr;
    logic        req_pred_taken;
    logic [63:0] req_pred_target;
    logic [8:0]  instr_bit_offset;
    logic [29:0] translated_paddr;
    logic        imem_waiting_for_response;

    assign bp_valid_o = (state == S_TLB_REQ) && !flush && !reset;
    assign bp_vaddr_o = pc;

    always_comb begin
        instr_bit_offset = {req_paddr[5:0], 3'b000};
        translated_paddr = itlb_paddr_i;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= S_TLB_REQ;
            pc <= reset_pc_i;
            req_pc <= '0;
            req_paddr <= '0;
            req_pred_taken <= 1'b0;
            req_pred_target <= '0;
            dcode_instr_o <= '0;
            dcode_pc_o <= '0;
            dcode_pred_taken_o <= 1'b0;
            dcode_pred_target_o <= '0;
            dcode_valid_o <= 1'b0;
            imem_valid_o <= 1'b0;
            imem_addr_o <= '0;
            imem_waiting_for_response <= 1'b0;
            itlb_valid_o <= 1'b0;
            itlb_vaddr_o <= '0;
        end else if (flush) begin
            state <= S_TLB_REQ;
            pc <= exe_target_i;
            req_pc <= '0;
            req_paddr <= '0;
            req_pred_taken <= 1'b0;
            req_pred_target <= '0;
            dcode_instr_o <= '0;
            dcode_pc_o <= '0;
            dcode_pred_taken_o <= 1'b0;
            dcode_pred_target_o <= '0;
            dcode_valid_o <= 1'b0;
            imem_valid_o <= 1'b0;
            imem_waiting_for_response <= 1'b0;
            itlb_valid_o <= 1'b0;
        end else begin
            if (imem_valid_o && imem_ready_i) begin
                imem_valid_o <= 1'b0;
            end

            case (state)
                S_TLB_REQ: begin
                    dcode_valid_o <= 1'b0;

                    if (itlb_ready_i) begin
                        req_pc <= pc;
                        req_pred_taken <= bp_taken_i;
                        req_pred_target <= bp_target_i;
                        itlb_vaddr_o <= pc;
                        itlb_valid_o <= 1'b1;
                        pc <= bp_taken_i ? bp_target_i : (pc + 64'd4);
                        state <= S_TLB_WAIT;
                    end
                end

                S_TLB_WAIT: begin
                    if (itlb_ready_i) begin
                        itlb_valid_o <= 1'b0;
                    end

                    if (itlb_hit_i) begin
                        req_paddr <= translated_paddr;
                        imem_addr_o <= {translated_paddr[29:6], 6'b0};
                        imem_valid_o <= 1'b1;
                        imem_waiting_for_response <= 1'b1;
                        state <= S_IMEM_WAIT;
                    end
                end

                S_IMEM_WAIT: begin
                    if (imem_waiting_for_response) begin
                        if (imem_valid_o && imem_ready_i) begin
                            imem_waiting_for_response <= 1'b0;
                        end
                    end else if (imem_valid_i && (req_paddr[29:6] == imem_addr_o[29:6])) begin
                        dcode_instr_o <= imem_rdata_i[instr_bit_offset +: 32];
                        dcode_pc_o <= req_pc;
                        dcode_pred_taken_o <= req_pred_taken;
                        dcode_pred_target_o <= req_pred_target;
                        dcode_valid_o <= 1'b1;
                        state <= S_OUT;
                    end
                end

                S_OUT: begin
                    if (dcode_ready_i) begin
                        dcode_valid_o <= 1'b0;
                        state <= S_TLB_REQ;
                    end
                end

                default: begin
                    state <= S_TLB_REQ;
                end
            endcase
        end
    end

endmodule

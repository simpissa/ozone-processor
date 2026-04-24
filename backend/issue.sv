`timescale 1ns / 1ps

import types::*;

module issue (
    input  logic                 flush,

    // Rename -> issue input bundle.
    input  logic                 valid_in,
    output logic                 ready_out,
    input  issue_payload_t       in_payload,

    // Shared issue payload bus seen by all functional units.
    output issue_payload_t       issue_payload,

    // Per-FU handshake. Every FU sees the shared payload bus, but only the
    // selected unit gets its valid asserted and contributes ready.
    output logic                 alu_issue_valid,
    input  logic                 alu_issue_ready,
    output logic                 shifter_issue_valid,
    input  logic                 shifter_issue_ready,
    output logic                 logic_issue_valid,
    input  logic                 logic_issue_ready,
    output logic                 agu_issue_valid,
    input  logic                 agu_issue_ready,
    output logic                 fpu_issue_valid,
    input  logic                 fpu_issue_ready,
    output logic                 mem_issue_valid,
    input  logic                 mem_issue_ready
);

    logic select_alu;
    logic select_shifter;
    logic select_logic;
    logic select_agu;
    logic select_fpu;
    logic select_mem;

    assign select_alu     = (in_payload.fu_select == FU_ALU);
    assign select_shifter = (in_payload.fu_select == FU_SHIFTER);
    assign select_logic   = (in_payload.fu_select == FU_LOGIC);
    assign select_agu     = (in_payload.fu_select == FU_AGU);
    assign select_fpu     = (in_payload.fu_select == FU_FPU);
    assign select_mem     = (in_payload.fu_select == FU_MEM);

    assign issue_payload = in_payload;

    assign alu_issue_valid     = valid_in && !flush && select_alu;
    assign shifter_issue_valid = valid_in && !flush && select_shifter;
    assign logic_issue_valid   = valid_in && !flush && select_logic;
    assign agu_issue_valid     = valid_in && !flush && select_agu;
    assign fpu_issue_valid     = valid_in && !flush && select_fpu;
    assign mem_issue_valid     = valid_in && !flush && select_mem;

    always_comb begin
        ready_out = 1'b0;

        if (!flush) begin
            unique case (in_payload.fu_select)
                FU_ALU:     ready_out = alu_issue_ready;
                FU_SHIFTER: ready_out = shifter_issue_ready;
                FU_LOGIC:   ready_out = logic_issue_ready;
                FU_AGU:     ready_out = agu_issue_ready;
                FU_FPU:     ready_out = fpu_issue_ready;
                FU_MEM:     ready_out = mem_issue_ready;
                FU_NONE:    ready_out = 1'b1;
                default:    ready_out = 1'b0;
            endcase
        end
    end

endmodule

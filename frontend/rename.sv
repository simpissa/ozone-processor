`timescale 1ns / 1ps

import frontend_types::*;

module rename #(
    parameter int unsigned ROB_TAG_W     = 6,
    parameter int unsigned NUM_ARCH_REGS = 31,
    parameter int unsigned FLAGS_ENTRY   = 31
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 flush,

    // Decoder -> rename input
    input  logic                 valid_in,
    output logic                 ready_out,

    // Decoder uop descriptor 
    input  fu_t                  fu_select,
    input  fu_op_t               fu_op,
    input  logic [4:0]           rd,
    input  logic                 r_dest_valid,
    input  logic [4:0]           rs1,
    input  logic                 rs1_valid,
    input  logic [4:0]           rs2,
    input  logic                 rs2_valid,
    input  logic [63:0]          imm,
    input  logic                 imm_valid,
    input  logic                 src1_is_pc,
    input  logic                 reads_flags,
    input  logic                 sets_flags,
    input  logic                 first_uop,
    input  logic                 last_uop,
    input  logic                 is_sequential,
    input  logic                 is_branch,
    input  logic                 is_eret,
    input  logic                 is_privileged,
    input  logic                 is_svc,
    input  logic [3:0]           cond,
    input  spr_t                 spr_id,
    input  logic [63:0]          pc,
    input  logic                 el,

    // Rename -> issue output
    output logic                 valid_out,
    input  logic                 ready_in,

    // Branch prediction sideband that should flow from fetch through decoder
    input  logic                 pred_taken,
    input  logic [63:0]          pred_target,

    // ROB allocation request
    output logic                 rob_alloc_valid,
    output logic [4:0]           rob_dest_reg,
    output logic                 rob_dest_valid,
    output logic [63:0]          rob_pc,
    output logic                 rob_is_branch,
    output logic                 rob_pred_taken,
    output logic [63:0]          rob_pred_target,
    output logic                 rob_first_uop,
    output logic                 rob_last_uop,
    output logic                 rob_is_eret,
    output logic                 rob_is_privileged,
    output logic                 rob_is_svc,
    output spr_t                 rob_spr_id,
    input  logic [ROB_TAG_W-1:0] rob_tag,
    input  logic                 rob_ready,

    // ROB completed-value lookup for source resolution.
    output logic                 rob_src1_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src1_lookup_tag,
    input  logic                 rob_src1_lookup_ready,
    input  logic [63:0]          rob_src1_lookup_value,
    output logic                 rob_src2_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src2_lookup_tag,
    input  logic                 rob_src2_lookup_ready,
    input  logic [63:0]          rob_src2_lookup_value,

    // Renamed uop for issue to reservation stations
    output fu_t                  out_fu_select,
    output fu_op_t               out_fu_op,
    output logic [ROB_TAG_W-1:0] out_dest_tag,
    output logic [63:0]          out_src1_value,
    output logic [ROB_TAG_W-1:0] out_src1_tag,
    output logic                 out_src1_ready,
    output logic [63:0]          out_src2_value,
    output logic [ROB_TAG_W-1:0] out_src2_tag,
    output logic                 out_src2_ready,
    output logic [63:0]          out_imm,
    output logic                 out_imm_valid,
    output logic [3:0]           out_cond
);

    logic can_accept_uop;
    logic rename_fire;

    // For now rename is a pure passthrough around ROB allocation, so it only
    // advances a uop when both the ROB and the downstream stage can take it.
    assign can_accept_uop   = !flush && rob_ready && ready_in;
    assign rename_fire      = valid_in && can_accept_uop;
    assign ready_out        = can_accept_uop;
    assign valid_out        = rename_fire;

    assign rob_alloc_valid  = rename_fire;
    assign rob_dest_reg     = rd;
    assign rob_dest_valid   = r_dest_valid && (rd != 5'd31);
    assign rob_pc           = pc;
    assign rob_is_branch    = is_branch;
    assign rob_pred_taken   = pred_taken;
    assign rob_pred_target  = pred_target;
    assign rob_first_uop    = first_uop;
    assign rob_last_uop     = last_uop;
    assign rob_is_eret      = is_eret;
    assign rob_is_privileged = is_privileged;
    assign rob_is_svc       = is_svc;
    assign rob_spr_id       = spr_id;

    assign rob_src1_lookup_valid = 1'b0;
    assign rob_src1_lookup_tag   = '0;
    assign rob_src2_lookup_valid = 1'b0;
    assign rob_src2_lookup_tag   = '0;

    assign out_fu_select    = fu_select;
    assign out_fu_op        = fu_op;
    assign out_dest_tag     = rob_tag;
    assign out_src1_value   = 64'd0;
    assign out_src1_tag     = '0;
    assign out_src1_ready   = 1'b0;
    assign out_src2_value   = 64'd0;
    assign out_src2_tag     = '0;
    assign out_src2_ready   = 1'b0;
    assign out_imm          = imm;
    assign out_imm_valid    = imm_valid;
    assign out_cond         = cond;

    // Major component: intake and stall control.
    // Final ready logic will gate decoder progress on ROB space and downstream
    // rename-output readiness. Reservation-station backpressure moves to the
    // later issue stage, so this file stops at a single renamed-uop channel.

    // Major component: architectural source lookup.
    // Source resolution will choose between PC, XZR, the previous sequential
    // uop tag, the architectural register file, and S-RAT tags. When
    // reads_flags is asserted, the lookup should use FLAGS_ENTRY instead of a
    // GPR source. If an S-RAT hit points at a completed ROB entry, rename will
    // use the ROB lookup ports above to fetch the waiting value instead of
    // forcing the consumer to wait for a CDB broadcast that already happened.
    // The ARF access details stay internal here because rename.md defines them
    // as part of the rename stage rather than as a separate external interface.

    // Major component: speculative RAT.
    // This holds one entry per architectural GPR (X0-X30) plus FLAGS_ENTRY for
    // NZCV. Accepted uops update the destination mapping with rob_tag; sets_flags
    // will also update FLAGS_ENTRY. Flush clears the speculative valid bits.

    // Major component: sequential uop latch.
    // A small register will remember the previously allocated ROB tag so a later
    // uop with is_sequential asserted can consume that producer as an implicit
    // dependency.

    // Major component: ROB allocation path.
    // Every accepted uop emits commit metadata here, including branch prediction
    // sideband and privileged/exception-related flags. FU_NONE and other
    // commit-only uops may need an extra ROB-side "complete on alloc" signal
    // once the ROB interface is implemented in detail.

    // Major component: renamed uop output.
    // These outputs carry the post-rename source operands, immediate, condition
    // code, FU select/op, and destination ROB tag into a future issue module.
    // This file intentionally does not fan out to per-RS interfaces.

    // Flush behavior.
    // The eventual implementation should clear speculative rename state, clear
    // the sequential-uop latch, and suppress downstream valid traffic on flush.

endmodule

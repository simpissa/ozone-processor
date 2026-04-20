`timescale 1ns / 1ps

import frontend_types::*;

module rename #(
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
    input  uop_t                 uop,
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

    // ROB commit interface for updating committed architectural state (ARF)
    input  logic                 rob_commit_valid,
    input  logic [ROB_TAG_W-1:0] rob_commit_tag,
    input  logic [4:0]           rob_commit_dest_reg,
    input  logic                 rob_commit_dest_valid,
    input  logic [63:0]          rob_commit_value,
    input  logic                 rob_commit_sets_flags,
    input  logic [63:0]          rob_commit_flags_value,

    // ROB completed-value lookup for source resolution.
    output logic                 rob_src1_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src1_lookup_tag,
    input  logic                 rob_src1_lookup_ready,
    input  logic [63:0]          rob_src1_lookup_value,
    output logic                 rob_src2_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src2_lookup_tag,
    input  logic                 rob_src2_lookup_ready,
    input  logic [63:0]          rob_src2_lookup_value,

    // Renamed uop for issue to reservation stations.
    output issue_payload_t       out_payload
);

    logic [63:0] arf [0:NUM_ARCH_REGS-1];
    logic [63:0] flags_arf;

    logic        srat_valid [0:FLAGS_ENTRY];
    logic [ROB_TAG_W-1:0] srat_tag [0:FLAGS_ENTRY];

    logic [ROB_TAG_W-1:0] prev_uop_tag;

    logic can_accept_uop;
    logic rename_fire;
    integer i;

    // Intake/stall control. Rename only accepts a uop when the ROB can allocate
    // an entry and the downstream issue path can consume the renamed uop.
    assign can_accept_uop   = !flush && rob_ready && ready_in;
    assign rename_fire      = valid_in && can_accept_uop;
    assign ready_out        = can_accept_uop;
    assign valid_out        = rename_fire;

    // ROB allocation path. Every accepted uop forwards its commit metadata to
    // the ROB and receives the allocated tag back on rob_tag.
    assign rob_alloc_valid   = rename_fire;
    assign rob_dest_reg      = uop.rd;
    assign rob_dest_valid    = uop.r_dest_valid && (uop.rd != 5'd31);
    assign rob_pc            = pc;
    assign rob_is_branch     = uop.is_branch;
    assign rob_pred_taken    = pred_taken;
    assign rob_pred_target   = pred_target;
    assign rob_first_uop     = uop.first_uop;
    assign rob_last_uop      = uop.last_uop;
    assign rob_is_eret       = uop.is_eret;
    assign rob_is_privileged = uop.is_privileged;
    assign rob_is_svc        = uop.is_svc;
    assign rob_spr_id        = uop.spr_id;

    // Committed architectural state, speculative RAT state, and the sequential
    // uop latch all live here. Flush clears speculative rename state only.
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_uop_tag <= '0;
            flags_arf    <= 64'd0;

            for (i = 0; i < NUM_ARCH_REGS; i = i + 1)
                arf[i] <= 64'd0;

            for (i = 0; i <= FLAGS_ENTRY; i = i + 1) begin
                srat_valid[i] <= 1'b0;
                srat_tag[i]   <= '0;
            end
        end else begin
            if (flush) begin
                prev_uop_tag <= '0;

                // Drop speculative mappings and fall back to committed ARF.
                for (i = 0; i <= FLAGS_ENTRY; i = i + 1) begin
                    srat_valid[i] <= 1'b0;
                    srat_tag[i]   <= '0;
                end
            end

            // rob commit, update ARF
            if (rob_commit_valid) begin
                if (rob_commit_dest_valid && (rob_commit_dest_reg != 5'd31)) begin
                    arf[rob_commit_dest_reg] <= rob_commit_value;

                    if (srat_valid[rob_commit_dest_reg] && (srat_tag[rob_commit_dest_reg] == rob_commit_tag)) begin
                        srat_valid[rob_commit_dest_reg] <= 1'b0;
                        srat_tag[rob_commit_dest_reg]   <= '0;
                    end
                end

                if (rob_commit_sets_flags) begin
                    flags_arf <= rob_commit_flags_value;

                    if (srat_valid[FLAGS_ENTRY] && (srat_tag[FLAGS_ENTRY] == rob_commit_tag)) begin
                        srat_valid[FLAGS_ENTRY] <= 1'b0;
                        srat_tag[FLAGS_ENTRY]   <= '0;
                    end
                end
            end

            if (rename_fire) begin
                prev_uop_tag <= rob_tag;

                if (uop.r_dest_valid && (uop.rd != 5'd31)) begin
                    srat_valid[uop.rd] <= 1'b1;
                    srat_tag[uop.rd]   <= rob_tag;
                end

                if (uop.sets_flags) begin
                    srat_valid[FLAGS_ENTRY] <= 1'b1;
                    srat_tag[FLAGS_ENTRY]   <= rob_tag;
                end
            end
        end
    end

    // Source resolution. Each source chooses between PC, the sequential-uop
    // dependency, committed ARF state, or a speculative ROB tag/value lookup.
    always_comb begin
        rob_src1_lookup_valid = 1'b0;
        rob_src1_lookup_tag   = '0;
        rob_src2_lookup_valid = 1'b0;
        rob_src2_lookup_tag   = '0;

        out_payload            = '0;
        out_payload.fu_select  = uop.fu_select;
        out_payload.fu_op      = uop.fu_op;
        out_payload.dest_tag   = rename_fire ? rob_tag : '0;
        out_payload.imm        = uop.imm;
        out_payload.imm_valid  = uop.imm_valid;
        out_payload.cond       = uop.cond;

        // Unused sources are modeled as ready-zero because the current issue
        // interface does not carry explicit src-valid bits.
        out_payload.src1_ready = 1'b1;
        out_payload.src2_ready = 1'b1;

        if (!flush && valid_in) begin
            if (uop.src1_is_pc) begin
                out_payload.src1_value = pc;
            end else if (uop.is_sequential) begin
                rob_src1_lookup_valid = 1'b1;
                rob_src1_lookup_tag   = prev_uop_tag;

                if (rob_src1_lookup_ready)
                    out_payload.src1_value = rob_src1_lookup_value;
                else begin
                    out_payload.src1_tag   = prev_uop_tag;
                    out_payload.src1_ready = 1'b0;
                end
            end else if (uop.reads_flags) begin
                if (!srat_valid[FLAGS_ENTRY])
                    out_payload.src1_value = flags_arf;
                else begin
                    rob_src1_lookup_valid = 1'b1;
                    rob_src1_lookup_tag   = srat_tag[FLAGS_ENTRY];

                    if (rob_src1_lookup_ready)
                        out_payload.src1_value = rob_src1_lookup_value;
                    else begin
                        out_payload.src1_tag   = srat_tag[FLAGS_ENTRY];
                        out_payload.src1_ready = 1'b0;
                    end
                end
            end else if (uop.rs1_valid) begin
                if (uop.rs1 == 5'd31)
                    out_payload.src1_value = 64'd0;
                else if (!srat_valid[uop.rs1])
                    out_payload.src1_value = arf[uop.rs1];
                else begin
                    rob_src1_lookup_valid = 1'b1;
                    rob_src1_lookup_tag   = srat_tag[uop.rs1];

                    if (rob_src1_lookup_ready)
                        out_payload.src1_value = rob_src1_lookup_value;
                    else begin
                        out_payload.src1_tag   = srat_tag[uop.rs1];
                        out_payload.src1_ready = 1'b0;
                    end
                end
            end

            if (uop.rs2_valid) begin
                if (uop.rs2 == 5'd31)
                    out_payload.src2_value = 64'd0;
                else if (!srat_valid[uop.rs2])
                    out_payload.src2_value = arf[uop.rs2];
                else begin
                    rob_src2_lookup_valid = 1'b1;
                    rob_src2_lookup_tag   = srat_tag[uop.rs2];

                    if (rob_src2_lookup_ready)
                        out_payload.src2_value = rob_src2_lookup_value;
                    else begin
                        out_payload.src2_tag   = srat_tag[uop.rs2];
                        out_payload.src2_ready = 1'b0;
                    end
                end
            end
        end
    end

endmodule

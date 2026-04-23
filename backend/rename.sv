`timescale 1ns / 1ps

import types::*;

module rename #(
    parameter int unsigned NUM_ARCH_REGS   = 31
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
    output logic                 rob_is_store,
    output logic                 rob_pred_taken,
    output logic [63:0]          rob_pred_target,
    output logic                 rob_first_uop,
    output logic                 rob_last_uop,
    output logic                 rob_is_eret,
    output logic                 rob_is_msr,
    output logic                 rob_is_mrs,
    output logic                 rob_is_privileged,
    output logic                 rob_is_svc,
    output logic                 rob_sets_flags,
    output spr_t                 rob_spr_id,
    output logic                 rob_alloc_self_ready,
    input  logic [ROB_TAG_W-1:0] rob_tag,
    input  logic                 rob_ready,

    // ROB commit interface for updating committed architectural state (ARF)
    input  logic                 rob_commit_gpr_valid,
    input  logic [ROB_TAG_W-1:0] rob_commit_tag,
    input  logic [4:0]           rob_commit_gpr_rd,
    input  logic [63:0]          rob_commit_gpr_value,

    // flags commit
    input  logic                 rob_commit_flags_valid,
    input  logic [3:0]           rob_commit_flags_value,

    // spr commit
    input  logic                 rob_commit_spr_valid,
    input  spr_t                 rob_commit_spr_id,
    input  logic [63:0]          rob_commit_spr_value,

    // ROB completed-value lookup for source resolution.
    output logic                 rob_src1_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src1_lookup_tag,
    input  logic                 rob_src1_lookup_hit_ready,
    input  logic [63:0]          rob_src1_lookup_value,
    output logic                 rob_src2_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src2_lookup_tag,
    input  logic                 rob_src2_lookup_hit_ready,
    input  logic [63:0]          rob_src2_lookup_value,

    // Renamed uop for issue to reservation stations.
    output issue_payload_t       out_payload
);

    logic [63:0]          gpr_arf [0:NUM_ARCH_REGS-1];
    logic [3:0]           flags_reg;
    logic [63:0]          sprf [0:NUM_SPRS-1];

    logic                 gpr_srat_valid [0:NUM_ARCH_REGS-1];
    logic [ROB_TAG_W-1:0] gpr_srat_tag [0:NUM_ARCH_REGS-1];
    logic                 flags_srat_valid;
    logic [ROB_TAG_W-1:0] flags_srat_tag;
    logic                 spr_srat_valid [0:NUM_SPRS-1];
    logic [ROB_TAG_W-1:0] spr_srat_tag [0:NUM_SPRS-1];

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
    assign rob_dest_valid    = uop.r_dest_valid && (uop.rd != 5'd31) && !uop.is_store;
    assign rob_pc            = pc;
    assign rob_is_branch     = uop.is_branch;
    assign rob_is_store      = uop.is_store;
    assign rob_pred_taken    = pred_taken;
    assign rob_pred_target   = pred_target;
    assign rob_first_uop     = uop.first_uop;
    assign rob_last_uop      = uop.last_uop;
    assign rob_is_eret       = uop.is_eret;
    assign rob_is_msr        = uop.is_msr;
    assign rob_is_mrs        = uop.is_mrs;
    assign rob_is_privileged = uop.is_privileged;
    assign rob_is_svc        = uop.is_svc;
    assign rob_sets_flags    = uop.sets_flags;
    assign rob_spr_id        = uop.spr_id;
    assign rob_alloc_self_ready = (uop.fu_select == FU_NONE);

    // Committed GPR/flags/SPR state, speculative rename state, and the
    // sequential-uop latch all live here. Flush clears speculative state only.
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_uop_tag <= '0;
            flags_reg    <= '0;

            for (i = 0; i < NUM_ARCH_REGS; i = i + 1) begin
                gpr_arf[i]        <= 64'd0;
                gpr_srat_valid[i] <= 1'b0;
                gpr_srat_tag[i]   <= '0;
            end

            flags_srat_valid <= 1'b0;
            flags_srat_tag   <= '0;

            for (i = 0; i < NUM_SPRS; i = i + 1) begin
                sprf[i]          <= 64'd0;
                spr_srat_valid[i] <= 1'b0;
                spr_srat_tag[i]   <= '0;
            end
        end else begin
            if (flush) begin
                prev_uop_tag <= '0;

                // Drop speculative mappings and fall back to committed state.
                for (i = 0; i < NUM_ARCH_REGS; i = i + 1) begin
                    gpr_srat_valid[i] <= 1'b0;
                    gpr_srat_tag[i]   <= '0;
                end

                flags_srat_valid <= 1'b0;
                flags_srat_tag   <= '0;

                for (i = 0; i < NUM_SPRS; i = i + 1) begin
                    spr_srat_valid[i] <= 1'b0;
                    spr_srat_tag[i]   <= '0;
                end
            end

            // rob commit, update ARF and clears stale speculative
            // mappings that still point at the retiring ROB entry.
            if (rob_commit_gpr_valid && (rob_commit_gpr_rd != 5'd31)) begin
                gpr_arf[rob_commit_gpr_rd] <= rob_commit_gpr_value;

                if (gpr_srat_valid[rob_commit_gpr_rd] && (gpr_srat_tag[rob_commit_gpr_rd] == rob_commit_tag)) begin
                    gpr_srat_valid[rob_commit_gpr_rd] <= 1'b0;
                    gpr_srat_tag[rob_commit_gpr_rd]   <= '0;
                end
            end

            // rob commit, update flags
            if (rob_commit_flags_valid) begin
                flags_reg <= rob_commit_flags_value;

                if (flags_srat_valid && (flags_srat_tag == rob_commit_tag)) begin
                    flags_srat_valid <= 1'b0;
                    flags_srat_tag   <= '0;
                end
            end

            // rob commit, update sprs
            if (rob_commit_spr_valid && (rob_commit_spr_id != SPR_INVALID)) begin
                sprf[rob_commit_spr_id] <= rob_commit_spr_value;

                if (spr_srat_valid[rob_commit_spr_id] && (spr_srat_tag[rob_commit_spr_id] == rob_commit_tag)) begin
                    spr_srat_valid[rob_commit_spr_id] <= 1'b0;
                    spr_srat_tag[rob_commit_spr_id]   <= '0;
                end
            end

            if (rename_fire) begin
                prev_uop_tag <= rob_tag;

                if (uop.r_dest_valid && (uop.rd != 5'd31) && !uop.is_store) begin
                    gpr_srat_valid[uop.rd] <= 1'b1;
                    gpr_srat_tag[uop.rd]   <= rob_tag;
                end

                if (uop.sets_flags) begin
                    flags_srat_valid <= 1'b1;
                    flags_srat_tag   <= rob_tag;
                end

                if (uop.is_msr && (uop.spr_id != SPR_INVALID)) begin
                    spr_srat_valid[uop.spr_id] <= 1'b1;
                    spr_srat_tag[uop.spr_id]   <= rob_tag;
                end
            end
        end
    end

    // Source resolution. Each source chooses between PC, the sequential-uop
    // dependency, committed GPR/flags/SPR state, or a speculative ROB lookup.
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

        if (!flush && valid_in) begin
            
            // --- src1 --- 
            if (uop.src1_is_pc) begin
                out_payload.src1_valid = 1'b1;
                out_payload.src1_ready = 1'b1;
                out_payload.src1_value = pc;
            end else if (uop.is_sequential) begin
                out_payload.src1_valid = 1'b1;
                rob_src1_lookup_valid = 1'b1;
                rob_src1_lookup_tag   = prev_uop_tag;

                if (rob_src1_lookup_hit_ready) begin
                    // value found in rob
                    out_payload.src1_ready = 1'b1;
                    out_payload.src1_value = rob_src1_lookup_value;
                end else begin
                    out_payload.src1_tag   = prev_uop_tag;
                    out_payload.src1_ready = 1'b0;
                end
            end else if (uop.reads_flags) begin
                out_payload.src1_valid = 1'b1;

                if (!flags_srat_valid) begin
                    out_payload.src1_ready = 1'b1;
                    out_payload.src1_value = {{60{1'b0}}, flags_reg};
                end else begin
                    rob_src1_lookup_valid = 1'b1;
                    rob_src1_lookup_tag   = flags_srat_tag;

                    if (rob_src1_lookup_hit_ready) begin
                        out_payload.src1_ready = 1'b1;
                        out_payload.src1_value = rob_src1_lookup_value;
                    end else begin
                        out_payload.src1_tag   = flags_srat_tag;
                        out_payload.src1_ready = 1'b0;
                    end
                end
            end else if ((uop.is_mrs || uop.is_eret) && (uop.spr_id != SPR_INVALID)) begin
                out_payload.src1_valid = 1'b1;

                if (!spr_srat_valid[uop.spr_id]) begin
                    out_payload.src1_ready = 1'b1;
                    out_payload.src1_value = sprf[uop.spr_id];
                end else begin
                    rob_src1_lookup_valid = 1'b1;
                    rob_src1_lookup_tag   = spr_srat_tag[uop.spr_id];

                    if (rob_src1_lookup_hit_ready) begin
                        out_payload.src1_ready = 1'b1;
                        out_payload.src1_value = rob_src1_lookup_value;
                    end else begin
                        out_payload.src1_tag   = spr_srat_tag[uop.spr_id];
                        out_payload.src1_ready = 1'b0;
                    end
                end
            end else if (uop.rs1_valid) begin
                out_payload.src1_valid = 1'b1;

                // assume X31 is XZR TODO: make sure this is right
                if (uop.rs1 == 5'd31) begin
                    out_payload.src1_ready = 1'b1;
                    out_payload.src1_value = 64'd0;
                end else if (!gpr_srat_valid[uop.rs1]) begin
                    // not in srat, can look up in arf
                    out_payload.src1_ready = 1'b1;
                    out_payload.src1_value = gpr_arf[uop.rs1];
                end else begin
                    rob_src1_lookup_valid = 1'b1;
                    rob_src1_lookup_tag   = gpr_srat_tag[uop.rs1];

                    if (rob_src1_lookup_hit_ready) begin
                        out_payload.src1_ready = 1'b1;
                        out_payload.src1_value = rob_src1_lookup_value;
                    end else begin
                        out_payload.src1_tag   = gpr_srat_tag[uop.rs1];
                        out_payload.src1_ready = 1'b0;
                    end
                end
            end

            // --- src2 ---
            if (uop.rs2_valid) begin
                out_payload.src2_valid = 1'b1;

                if (uop.rs2 == 5'd31) begin
                    out_payload.src2_ready = 1'b1;
                    out_payload.src2_value = 64'd0;
                end else if (!gpr_srat_valid[uop.rs2]) begin
                    out_payload.src2_ready = 1'b1;
                    out_payload.src2_value = gpr_arf[uop.rs2];
                end else begin
                    rob_src2_lookup_valid = 1'b1;
                    rob_src2_lookup_tag   = gpr_srat_tag[uop.rs2];

                    if (rob_src2_lookup_hit_ready) begin
                        out_payload.src2_ready = 1'b1;
                        out_payload.src2_value = rob_src2_lookup_value;
                    end else begin
                        out_payload.src2_tag   = gpr_srat_tag[uop.rs2];
                        out_payload.src2_ready = 1'b0;
                    end
                end
            end
        end
    end

endmodule

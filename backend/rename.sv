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

    // Architectural EL state, exposed to frontend (iTLB/fetch).
    output logic                 el_out,

    // Current committed NZCV, exposed for ROB to pack into SPSR_EL1 at
    // exception entry.
    output logic [3:0]           flags_out,
    output logic [63:0]          spr_ttbr0_el1_out,
    output logic [63:0]          spr_vbar_el1_out,
    output logic [63:0]          spr_elr_el1_out,

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
    output logic                 rob_is_conditional,
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
    output logic [63:0]          rob_exception_pc,
    output logic                 rob_exception_el,
    output logic                 rob_alloc_self_ready,
    output logic                 rob_alloc_exception,
    output logic [3:0]           rob_alloc_exception_code,
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

    // exception-time spr writes
    input  logic                 rob_commit_exc_elr_valid,
    input  logic [63:0]          rob_commit_exc_elr_value,
    input  logic                 rob_commit_exc_spsr_valid,
    input  logic [63:0]          rob_commit_exc_spsr_value,
    input  logic                 rob_commit_exc_esr_valid,
    input  logic [63:0]          rob_commit_exc_esr_value,

    // EL state transitions driven from ROB commit
    input  logic                 rob_commit_is_exception,
    input  logic                 rob_commit_is_eret,

    // ROB completed-value lookup for source resolution.
    output logic                 rob_src1_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src1_lookup_tag,
    output logic                 rob_src1_lookup_flags,
    input  logic                 rob_src1_lookup_hit_ready,
    input  logic [63:0]          rob_src1_lookup_value,
    output logic                 rob_src2_lookup_valid,
    output logic [ROB_TAG_W-1:0] rob_src2_lookup_tag,
    output logic                 rob_src2_lookup_flags,
    input  logic                 rob_src2_lookup_hit_ready,
    input  logic [63:0]          rob_src2_lookup_value,

    // Renamed uop for issue to reservation stations.
    output issue_payload_t       out_payload
);

    logic [63:0]          gpr_arf [0:NUM_ARCH_REGS-1];
    logic [3:0]           flags_reg;
    logic [63:0]          sprf [0:NUM_SPRS-1];

    // Architectural EL flop. Updated only at commit (exception entry / ERET),
    // both of which flush the pipeline so no speculative EL is needed.
    // EL1 = 1'b1, EL0 = 1'b0. Reset enters EL1 per spec.
    logic                 el_reg;

    // Allocation-time privilege violation detection.
    logic                 priv_violation;

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
    assign can_accept_uop   = !flush && rob_ready;
    assign rename_fire      = valid_in && can_accept_uop && ready_in;
    assign ready_out        = can_accept_uop && ready_in;
    assign valid_out        = valid_in && can_accept_uop;

    // ROB allocation path. Every accepted uop forwards its commit metadata to
    // the ROB and receives the allocated tag back on rob_tag.
    assign rob_alloc_valid   = rename_fire;
    assign rob_dest_reg      = uop.rd;
    assign rob_dest_valid    = uop.r_dest_valid && (uop.rd != 5'd31) && !uop.is_store;
    assign rob_pc            = pc;
    assign rob_is_branch     = uop.is_branch;
    assign rob_is_conditional = uop.is_conditional;
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
    assign rob_exception_pc  = uop.is_svc ? (pc + 64'd4) : pc;
    assign rob_exception_el  = el_reg;
    assign rob_alloc_self_ready = (uop.fu_select == FU_NONE);
    assign el_out            = el_reg;
    assign flags_out         = flags_reg;
    assign spr_ttbr0_el1_out = sprf[SPR_TTBR0_EL1[SPR_IDX_W-1:0]];
    assign spr_vbar_el1_out  = sprf[SPR_VBAR_EL1[SPR_IDX_W-1:0]];
    assign spr_elr_el1_out   = sprf[SPR_ELR_EL1[SPR_IDX_W-1:0]];

    // Privileged uop dispatched while not at EL1 traps at allocation. The uop
    // never reaches an FU; ROB sees it as a ready exception and handles it
    // when it reaches the head.
    assign priv_violation           = uop.is_privileged && (el_reg == 1'b0);
    assign rob_alloc_exception      = uop.is_svc || priv_violation;
    assign rob_alloc_exception_code = priv_violation ? EXC_CODE_PRIV
                                       : (uop.is_svc ? EXC_CODE_SVC : EXC_CODE_NONE);

    // Committed GPR/flags/SPR state, speculative rename state, and the
    // sequential-uop latch all live here. Flush clears speculative state only.
    always_ff @(posedge clk) begin
        if (rst) begin
            prev_uop_tag <= '0;
            flags_reg    <= '0;
            el_reg       <= 1'b1; // reset enters EL1

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
            // PSTATE transitions at commit. Exception entry forces EL1
            // (flags are saved into SPSR by ROB, see commit_exc_spsr_value).
            // ERET restores both EL (bit [0]) and NZCV (bits [31:28]) from
            // the committed SPSR_EL1. Any other commit leaves PSTATE alone.
            if (rob_commit_is_exception) begin
                el_reg <= 1'b1;
            end else if (rob_commit_is_eret) begin
                el_reg    <= sprf[SPR_SPSR_EL1[SPR_IDX_W-1:0]][0];
                flags_reg <= sprf[SPR_SPSR_EL1[SPR_IDX_W-1:0]][31:28];
            end
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
                sprf[rob_commit_spr_id[SPR_IDX_W-1:0]] <= rob_commit_spr_value;

                if (spr_srat_valid[rob_commit_spr_id[SPR_IDX_W-1:0]] && (spr_srat_tag[rob_commit_spr_id[SPR_IDX_W-1:0]] == rob_commit_tag)) begin
                    spr_srat_valid[rob_commit_spr_id[SPR_IDX_W-1:0]] <= 1'b0;
                    spr_srat_tag[rob_commit_spr_id[SPR_IDX_W-1:0]]   <= '0;
                end
            end

            if (rob_commit_exc_elr_valid) begin
                sprf[SPR_ELR_EL1[SPR_IDX_W-1:0]] <= rob_commit_exc_elr_value;
            end

            if (rob_commit_exc_spsr_valid) begin
                sprf[SPR_SPSR_EL1[SPR_IDX_W-1:0]] <= rob_commit_exc_spsr_value;
            end

            if (rob_commit_exc_esr_valid) begin
                sprf[SPR_ESR_EL1[SPR_IDX_W-1:0]] <= rob_commit_exc_esr_value;
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
                    spr_srat_valid[uop.spr_id[SPR_IDX_W-1:0]] <= 1'b1;
                    spr_srat_tag[uop.spr_id[SPR_IDX_W-1:0]]   <= rob_tag;
                end
            end
        end
    end

    // Source resolution. Each source chooses between PC, the sequential-uop
    // dependency, committed GPR/flags/SPR state, or a speculative ROB lookup.
    always_comb begin
        rob_src1_lookup_valid = 1'b0;
        rob_src1_lookup_tag   = '0;
        rob_src1_lookup_flags = 1'b0;
        rob_src2_lookup_valid = 1'b0;
        rob_src2_lookup_tag   = '0;
        rob_src2_lookup_flags = 1'b0;

        out_payload            = '0;
        out_payload.fu_select  = uop.fu_select;
        out_payload.fu_op      = uop.fu_op;
        out_payload.set_flags  = uop.sets_flags;
        out_payload.dest_valid = uop.r_dest_valid && (uop.rd != 5'd31) && !uop.is_store;
        out_payload.dest_tag   = (valid_in && can_accept_uop) ? rob_tag : '0;
        out_payload.imm        = uop.imm;
        out_payload.imm_valid  = uop.imm_valid;
        out_payload.cond       = uop.cond;

        if (!flush && valid_in) begin
            
            // --- src1 --- 
            if (uop.src1_is_pc) begin
                out_payload.src1_valid = 1'b1;
                out_payload.src1_ready = 1'b1;
                out_payload.src1_value = pc;
            end else if (uop.src1_is_sequential) begin
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
                    rob_src1_lookup_flags = 1'b1;

                    if (rob_src1_lookup_hit_ready) begin
                        out_payload.src1_ready = 1'b1;
                        out_payload.src1_value = rob_src1_lookup_value;
                    end else begin
                        out_payload.src1_tag   = flags_srat_tag;
                        out_payload.src1_ready = 1'b0;
                    end
                end
            end else if (uop.is_mrs && (uop.spr_id != SPR_INVALID)) begin
                out_payload.src1_valid = 1'b1;

                if (!spr_srat_valid[uop.spr_id[SPR_IDX_W-1:0]]) begin
                    out_payload.src1_ready = 1'b1;
                    out_payload.src1_value = sprf[uop.spr_id[SPR_IDX_W-1:0]];
                end else begin
                    rob_src1_lookup_valid = 1'b1;
                    rob_src1_lookup_tag   = spr_srat_tag[uop.spr_id[SPR_IDX_W-1:0]];

                    if (rob_src1_lookup_hit_ready) begin
                        out_payload.src1_ready = 1'b1;
                        out_payload.src1_value = rob_src1_lookup_value;
                    end else begin
                        out_payload.src1_tag   = spr_srat_tag[uop.spr_id[SPR_IDX_W-1:0]];
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
            if (uop.src2_is_sequential) begin
                out_payload.src2_valid = 1'b1;
                rob_src2_lookup_valid = 1'b1;
                rob_src2_lookup_tag   = prev_uop_tag;

                if (rob_src2_lookup_hit_ready) begin
                    out_payload.src2_ready = 1'b1;
                    out_payload.src2_value = rob_src2_lookup_value;
                end else begin
                    out_payload.src2_tag   = prev_uop_tag;
                    out_payload.src2_ready = 1'b0;
                end
            end else if (uop.rs2_valid) begin
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

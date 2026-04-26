`timescale 1ns / 1ps

import types::*;

module rob #(
    parameter int unsigned ROB_SIZE = (1 << ROB_TAG_W),
    parameter logic [63:0] SYNC_EXCEPTION_OFFSET = 64'd1024,
    parameter logic [63:0] TERMINATE_VALUE = 64'hdead
) (
    input  logic                 clk,
    input  logic                 rst,

    // Rename -> ROB allocation path
    input  logic                 alloc_valid,
    output logic                 ready_out,
    output logic [ROB_TAG_W-1:0] alloc_tag,
    input  logic [63:0]          pc_in,
    input  logic [4:0]           dest_reg,
    input  logic                 dest_valid,
    input  logic                 dest_is_fp,
    input  logic                 is_branch_in,
    input  logic                 is_conditional_in,
    input  logic                 is_store_in,
    input  logic                 is_eret_in,
    input  logic                 is_svc_in,
    input  logic                 is_msr_in,
    input  logic                 is_mrs_in,
    input  logic                 is_privileged_in,
    input  logic                 sets_flags_in,
    input  spr_t                 spr_id_in,
    input  logic [63:0]          exception_pc_in,
    input  logic                 exception_el_in,
    input  logic                 first_uop_in,
    input  logic                 last_uop_in,
    input  logic [63:0]          pred_target,
    input  logic                 pred_taken,
    input  logic                 alloc_self_ready, // ready on allocation (nop)
    // Generic allocation-time exception (covers SVC, EL0 privilege violation,
    // and future fetch-side faults plumbed in from the frontend).
    input  logic                 alloc_exception_in,
    input  logic [3:0]           alloc_exception_code_in,

    // Rename lookup ports for completed ROB values
    input  logic                 src1_lookup_valid,
    input  logic [ROB_TAG_W-1:0] src1_lookup_tag,
    input  logic                 src1_lookup_flags,
    output logic                 src1_lookup_hit_ready,
    output logic [63:0]          src1_lookup_value,
    input  logic                 src2_lookup_valid,
    input  logic [ROB_TAG_W-1:0] src2_lookup_tag,
    input  logic                 src2_lookup_flags,
    output logic                 src2_lookup_hit_ready,
    output logic [63:0]          src2_lookup_value,

    // Common data bus broadcast
    input  fu_result_t           cdb_result,

    // ---Commit interface---
    // writeback to arf
    output logic                 commit_gpr_valid,
    output logic [4:0]           commit_gpr_rd,
    output logic [63:0]          commit_gpr_value,
    output logic [ROB_TAG_W-1:0] commit_tag,
    output logic                 commit_fp_valid,
    output logic [4:0]           commit_fp_rd,
    output logic [63:0]          commit_fp_value,

    // writeback to special registers
    output logic                 commit_spr_valid,
    output spr_t                 commit_spr_id,
    output logic [63:0]          commit_spr_value,

    // exception-time spr writes
    output logic                 commit_exc_elr_valid,
    output logic [63:0]          commit_exc_elr_value,
    output logic                 commit_exc_spsr_valid,
    output logic [63:0]          commit_exc_spsr_value,
    output logic                 commit_exc_esr_valid,
    output logic [63:0]          commit_exc_esr_value,

    // writeback to flags
    output logic                 commit_flags_valid,
    output logic [3:0]           commit_flags_value,

    // lsq commit
    output logic                 commit_store,
    output logic [ROB_TAG_W-1:0] commit_store_tag,

    // exceptions/redirections
    output logic [63:0]          redirect_pc, // to fetch; where to start after a flush
    output logic                 commit_is_eret,
    output logic                 commit_is_exception,
    output logic [3:0]           commit_exception_code,
    output logic [63:0]          commit_exception_pc,
    output logic                 commit_terminate,

    // output to branch predictor
    output logic                 resolveValid,
    output logic                 resolveIsBranch,
    output logic                 resolveIsConditional,
    output logic [63:0]          resolvePC,
    output logic                 resolveTaken,
    output logic [63:0]          resolveTarget,

    // External SPR state used by future commit-time redirects
    input  logic [63:0]          spr_vbar_el1,
    input  logic [63:0]          spr_elr_el1,
    // Current committed NZCV from rename, packed into SPSR_EL1 on exception
    // entry so ERET can restore it.
    input  logic [3:0]           current_flags_in,

    output logic                 flush,
    output logic [ROB_TAG_W:0]   num_entries,
    output logic                 full,
    output logic                 empty
);

    typedef struct packed {
        logic [63:0] pc;
        logic [63:0] exception_pc;
        logic [4:0]  arch_rd;
        logic        el;
        logic        rd_valid;
        logic        rd_is_fp;
        logic        is_branch;
        logic        is_conditional;
        logic        is_store;
        logic        is_eret;
        logic        is_svc;
        logic        is_msr;
        logic        is_mrs;
        logic        is_privileged;
        logic        sets_flags;
        spr_t        spr_id;
        logic        first_uop;
        logic        last_uop;
        logic [63:0] predicted_target;
        logic        predicted_taken;
        logic        ready;
        logic [63:0] result;
        logic [3:0]  flags;
        logic        flags_valid;
        logic        exception;
        logic [3:0]  exception_code;
        logic        valid;
    } rob_entry_t;

    rob_entry_t entries [0:ROB_SIZE-1];
    rob_entry_t entries_n [0:ROB_SIZE-1];

    // Head/tail pointers use one extra wrap bit
    logic [ROB_TAG_W:0]   head;
    logic [ROB_TAG_W:0]   tail;
    logic [ROB_TAG_W:0]   head_n;
    logic [ROB_TAG_W:0]   tail_n;
    logic [ROB_TAG_W-1:0] head_idx;
    logic [ROB_TAG_W-1:0] tail_idx;

    rob_entry_t           head_entry;
    logic                 head_can_commit;
    logic                 head_branch_mispredict;
    logic                 head_branch_to_zero;
    logic                 head_zero_terminates;
    logic                 head_eret_redirect;
    logic [3:0]           head_exception_code;
    logic                 DBG;

    initial begin
        if (!$value$plusargs("BDEBUG=%b", DBG)) begin
            DBG = 1'b0;
        end
    end

    assign head_idx   = head[ROB_TAG_W-1:0];
    assign tail_idx   = tail[ROB_TAG_W-1:0];
    assign empty      = (head == tail);
    assign full       = (head[ROB_TAG_W-1:0] == tail[ROB_TAG_W-1:0]) &&
                        (head[ROB_TAG_W] != tail[ROB_TAG_W]);
    assign num_entries = tail - head;

    assign alloc_tag = tail_idx;
    assign ready_out = !full;

    // rob lookup from rename
    always_comb begin
        src1_lookup_hit_ready = 1'b0;
        src1_lookup_value = 64'd0;
        src2_lookup_hit_ready = 1'b0;
        src2_lookup_value = 64'd0;

        if (src1_lookup_valid) begin
            if (src1_lookup_flags) begin
                if (cdb_result.valid && (cdb_result.tag == src1_lookup_tag) && cdb_result.flags_valid) begin
                    src1_lookup_hit_ready = 1'b1;
                    src1_lookup_value = {{60{1'b0}}, cdb_result.flags};
                end else begin
                    src1_lookup_hit_ready = entries[src1_lookup_tag].flags_valid;
                    src1_lookup_value = {{60{1'b0}}, entries[src1_lookup_tag].flags};
                end
            end else if (cdb_result.valid && (cdb_result.tag == src1_lookup_tag)) begin
                src1_lookup_hit_ready = 1'b1;
                src1_lookup_value = cdb_result.value;
            end else begin
                src1_lookup_hit_ready = entries[src1_lookup_tag].ready;
                src1_lookup_value = entries[src1_lookup_tag].result;
            end
        end

        if (src2_lookup_valid) begin
            if (src2_lookup_flags) begin
                if (cdb_result.valid && (cdb_result.tag == src2_lookup_tag) && cdb_result.flags_valid) begin
                    src2_lookup_hit_ready = 1'b1;
                    src2_lookup_value = {{60{1'b0}}, cdb_result.flags};
                end else begin
                    src2_lookup_hit_ready = entries[src2_lookup_tag].flags_valid;
                    src2_lookup_value = {{60{1'b0}}, entries[src2_lookup_tag].flags};
                end
            end else if (cdb_result.valid && (cdb_result.tag == src2_lookup_tag)) begin
                src2_lookup_hit_ready = 1'b1;
                src2_lookup_value = cdb_result.value;
            end else begin
                src2_lookup_hit_ready = entries[src2_lookup_tag].ready;
                src2_lookup_value = entries[src2_lookup_tag].result;
            end
        end
    end

    always_comb begin
        // defaults
        commit_gpr_valid       = 1'b0;
        commit_gpr_rd          = '0;
        commit_gpr_value       = 64'd0;
        commit_tag             = '0;
        commit_fp_valid        = 1'b0;
        commit_fp_rd           = '0;
        commit_fp_value        = 64'd0;
        commit_spr_valid       = 1'b0;
        commit_spr_id          = SPR_INVALID;
        commit_spr_value       = 64'd0;
        commit_exc_elr_valid   = 1'b0;
        commit_exc_elr_value   = 64'd0;
        commit_exc_spsr_valid  = 1'b0;
        commit_exc_spsr_value  = 64'd0;
        commit_exc_esr_valid   = 1'b0;
        commit_exc_esr_value   = 64'd0;
        commit_flags_valid     = 1'b0;
        commit_flags_value     = '0;
        commit_store           = 1'b0;
        commit_store_tag       = '0;
        redirect_pc            = 64'd0;
        commit_is_eret         = 1'b0;
        commit_is_exception    = 1'b0;
        commit_exception_code  = EXC_CODE_NONE;
        commit_exception_pc    = 64'd0;
        commit_terminate       = 1'b0;
        resolveValid           = 1'b0;
        resolveIsBranch        = 1'b0;
        resolveIsConditional   = 1'b0;
        resolvePC              = 64'd0;
        resolveTaken           = 1'b0;
        resolveTarget          = 64'd0;
        flush                  = 1'b0;

        head_n = head;
        tail_n = tail;

        entries_n = entries;

        if (cdb_result.valid) begin
            // Branch completions use value as the resolved next PC, so the
            // ROB consumes the CDB as the canonical next-state view.
            entries_n[cdb_result.tag].result         = cdb_result.value;
            entries_n[cdb_result.tag].flags          = cdb_result.flags;
            entries_n[cdb_result.tag].flags_valid    = cdb_result.flags_valid;
            entries_n[cdb_result.tag].ready          = 1'b1;
            entries_n[cdb_result.tag].exception      = cdb_result.exception;
            entries_n[cdb_result.tag].exception_code = cdb_result.exception_code;
        end

        head_entry = entries_n[head_idx];
        head_can_commit = head_entry.valid && head_entry.ready;
        head_branch_mispredict = head_entry.is_branch &&
                                 head_entry.last_uop &&
                                 (head_entry.result != head_entry.predicted_target);
        // Spec hardcoding: the only ifetch fault we need to model is
        // userspace RET to 0x0 terminating the program. Detect it at branch
        // resolution and synthesize an Instruction Fetch Memory Abort here
        // rather than letting fetch try to walk an unmapped page 0.
        head_branch_to_zero = head_entry.is_branch &&
                              head_entry.last_uop &&
                              (head_entry.result == 64'd0);
        head_zero_terminates = head_branch_to_zero && (spr_vbar_el1 == 64'd0);
        head_eret_redirect = head_entry.is_eret && head_entry.last_uop;
        head_exception_code = head_branch_to_zero ? EXC_CODE_SYNC :
                              (head_entry.exception_code == EXC_CODE_NONE) ? EXC_CODE_SYNC : head_entry.exception_code;

        // in-order commit
        if (head_can_commit) begin
            commit_tag = head_idx;

            if (head_zero_terminates) begin
                commit_terminate = 1'b1;
            end else if (head_entry.exception || head_branch_to_zero) begin
                // ---EXCEPTIONS---
                /*
                On exception
                1. save faulting PC to ELR (curr PC + 4 for SVC,
                   resolved branch target for synthesized ifetch abort)
                2. write old PSTATE (currently only EL) to SPSR
                3. write EXC_CODE_* to ESR 
                */
                commit_is_exception   = 1'b1;
                commit_exception_code = head_exception_code;
                commit_exception_pc   = head_branch_to_zero ? head_entry.pc : head_entry.exception_pc;
                commit_exc_elr_valid  = 1'b1;
                commit_exc_elr_value  = head_branch_to_zero ? head_entry.pc : head_entry.exception_pc;
                commit_exc_spsr_valid = 1'b1;
                commit_exc_spsr_value = {63'd0, head_entry.el};
                commit_exc_esr_valid  = 1'b0;
                commit_exc_esr_value  = 64'd0;
                redirect_pc           = spr_vbar_el1 + SYNC_EXCEPTION_OFFSET;
                flush                 = 1'b1;
            end else begin
                commit_gpr_valid = head_entry.rd_valid && !head_entry.rd_is_fp && !head_entry.is_store;
                commit_gpr_rd    = head_entry.arch_rd;
                commit_gpr_value = head_entry.result;
                commit_fp_valid  = head_entry.rd_valid && head_entry.rd_is_fp && !head_entry.is_store;
                commit_fp_rd     = head_entry.arch_rd;
                commit_fp_value  = head_entry.result;

                commit_spr_valid = head_entry.is_msr;
                commit_spr_id    = head_entry.spr_id;
                commit_spr_value = head_entry.result;

                commit_flags_valid = head_entry.sets_flags && head_entry.flags_valid;
                commit_flags_value = head_entry.flags;

                commit_store     = head_entry.is_store;
                commit_store_tag = head_idx;

                commit_terminate = head_entry.is_msr &&
                                   (head_entry.spr_id == SPR_ACTLR_EL1) &&
                                   (head_entry.result == TERMINATE_VALUE) &&
                                   head_entry.last_uop;
                if (head_branch_mispredict) begin
                    redirect_pc = head_entry.result;
                    flush              = 1'b1;
                end

                if (head_eret_redirect) begin
                    redirect_pc    = spr_elr_el1;
                    commit_is_eret     = 1'b1;
                    flush              = 1'b1;
                    if (DBG) begin
                        $display("ROB eret commit: tag=%0d pc=%016x redirect=%016x", head_idx, head_entry.pc, spr_elr_el1);
                    end
                end
            end

            if (head_entry.is_branch && head_entry.last_uop && !head_entry.exception && !head_branch_to_zero) begin
                resolveValid         = 1'b1;
                resolveIsBranch      = 1'b1;
                resolveIsConditional = head_entry.is_conditional;
                resolvePC            = head_entry.pc;
                resolveTaken         = (head_entry.result != (head_entry.pc + 64'd4));
                resolveTarget        = head_entry.result;
            end
        end

        if (flush) begin
            head_n = tail;
            tail_n = tail;

            entries_n = '{default: '{default: '0, spr_id: SPR_INVALID}};
        end else begin
            if (head_can_commit) begin
                entries_n[head_idx].valid = 1'b0;
                head_n                    = head + 1'b1;
            end

            // Allocation comes after commit so a new dispatch wins if both
            // target the same slot in a tiny/full-wrap ROB scenario.
            if (alloc_valid && ready_out) begin
                entries_n[tail_idx].pc               = pc_in;
                entries_n[tail_idx].exception_pc     = exception_pc_in;
                entries_n[tail_idx].arch_rd          = dest_reg;
                entries_n[tail_idx].rd_is_fp         = dest_is_fp;
                entries_n[tail_idx].el               = exception_el_in;
                entries_n[tail_idx].rd_valid         = dest_valid;
                entries_n[tail_idx].is_branch        = is_branch_in;
                entries_n[tail_idx].is_conditional   = is_conditional_in;
                entries_n[tail_idx].is_store         = is_store_in;
                entries_n[tail_idx].is_eret          = is_eret_in;
                entries_n[tail_idx].is_svc           = is_svc_in;
                entries_n[tail_idx].is_msr           = is_msr_in;
                entries_n[tail_idx].is_mrs           = is_mrs_in;
                entries_n[tail_idx].is_privileged    = is_privileged_in;
                entries_n[tail_idx].sets_flags       = sets_flags_in;
                entries_n[tail_idx].spr_id           = spr_id_in;
                entries_n[tail_idx].first_uop        = first_uop_in;
                entries_n[tail_idx].last_uop         = last_uop_in;
                entries_n[tail_idx].predicted_target = pred_target;
                entries_n[tail_idx].predicted_taken  = pred_taken;
                entries_n[tail_idx].ready            = alloc_self_ready || alloc_exception_in;
                entries_n[tail_idx].result           = 64'd0;
                entries_n[tail_idx].flags            = 4'd0;
                entries_n[tail_idx].flags_valid      = 1'b0;
                entries_n[tail_idx].exception        = alloc_exception_in;
                entries_n[tail_idx].exception_code   = alloc_exception_in ? alloc_exception_code_in : EXC_CODE_NONE;
                entries_n[tail_idx].valid            = 1'b1;
                tail_n                               = tail + 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head <= '0;
            tail <= '0;

            entries <= '{default: '{default: '0, spr_id: SPR_INVALID}};
        end else begin
            if (DBG && full && !(entries[head_idx].valid && entries[head_idx].ready)) begin
                $display("ROB full: head=%0d tail=%0d head_valid=%0b head_ready=%0b head_pc=%016x head_fu-ish branch=%0b store=%0b msr=%0b eret=%0b",
                         head, tail, entries[head_idx].valid, entries[head_idx].ready,
                         entries[head_idx].pc, entries[head_idx].is_branch,
                         entries[head_idx].is_store, entries[head_idx].is_msr,
                         entries[head_idx].is_eret);
            end
            head <= head_n;
            tail <= tail_n;

            entries <= entries_n;
        end
    end

endmodule

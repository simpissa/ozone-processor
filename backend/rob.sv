`timescale 1ns / 1ps

import types::*;

module rob #(
    parameter int unsigned ROB_SIZE = (1 << ROB_TAG_W)
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
    input  logic                 is_branch_in,
    input  logic                 is_store_in,
    input  logic                 is_eret_in,
    input  logic                 is_svc_in,
    input  logic                 is_msr_in,
    input  logic                 is_mrs_in,
    input  logic                 is_privileged_in,
    input  logic                 sets_flags_in,
    input  spr_t                 spr_id_in,
    input  logic                 first_uop_in,
    input  logic                 last_uop_in,
    input  logic [63:0]          pred_target,
    input  logic                 pred_taken,

    // Rename lookup ports for completed ROB values
    input  logic                 src1_lookup_valid,
    input  logic [ROB_TAG_W-1:0] src1_lookup_tag,
    output logic                 src1_lookup_hit_ready,
    output logic [63:0]          src1_lookup_value,
    input  logic                 src2_lookup_valid,
    input  logic [ROB_TAG_W-1:0] src2_lookup_tag,
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

    // writeback to special registers
    output logic                 commit_spr_valid,
    output spr_t                 commit_spr_id,
    output logic [63:0]          commit_spr_value,

    // writeback to flags
    output logic                 commit_flags_valid,
    output logic [3:0]           commit_flags_value,

    // lsq commit
    output logic                 commit_store,
    output logic [ROB_TAG_W-1:0] commit_store_tag,

    // exceptions/redirections
    output logic                 commit_redirect,
    output logic [63:0]          commit_redirect_pc,
    output logic                 commit_is_eret,
    output logic                 commit_is_exception,
    output logic [3:0]           commit_exception_code,
    output logic [63:0]          commit_exception_pc,
    output logic                 commit_terminate,

    // External SPR state used by future commit-time redirects
    input  logic [63:0]          spr_vbar_el1,
    input  logic [63:0]          spr_elr_el1,

    output logic                 flush,
    output logic [ROB_TAG_W:0]   num_entries,
    output logic                 full,
    output logic                 empty
);

    typedef struct packed {
        logic [63:0] pc;
        logic [4:0]  arch_rd;
        logic        rd_valid;
        logic        is_branch;
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

    // Head/tail pointers use one extra wrap bit
    logic [ROB_TAG_W:0]   head;
    logic [ROB_TAG_W:0]   tail;
    logic [ROB_TAG_W-1:0] head_idx;
    logic [ROB_TAG_W-1:0] tail_idx;

    integer i;

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
            if (cdb_result.valid && (cdb_result.tag == src1_lookup_tag)) begin
                src1_lookup_hit_ready = 1'b1;
                src1_lookup_value = cdb_result.value;
            end else begin
                src1_lookup_hit_ready = entries[src1_lookup_tag].ready;
                src1_lookup_value = entries[src1_lookup_tag].result;
            end
        end

        if (src2_lookup_valid) begin
            if (cdb_result.valid && (cdb_result.tag == src2_lookup_tag)) begin
                src2_lookup_hit_ready = 1'b1;
                src2_lookup_value = cdb_result.value;
            end else begin
                src2_lookup_hit_ready = entries[src2_lookup_tag].ready;
                src2_lookup_value = entries[src2_lookup_tag].result;
            end
        end
    end

    always_comb begin
        commit_gpr_valid       = 1'b0;
        commit_gpr_rd          = '0;
        commit_gpr_value       = 64'd0;
        commit_tag             = '0;
        commit_spr_valid       = 1'b0;
        commit_spr_id          = SPR_INVALID;
        commit_spr_value       = 64'd0;
        commit_flags_valid     = 1'b0;
        commit_flags_value     = '0;
        commit_store           = 1'b0;
        commit_store_tag       = '0;
        commit_redirect        = 1'b0;
        commit_redirect_pc     = 64'd0;
        commit_is_eret         = 1'b0;
        commit_is_exception    = 1'b0;
        commit_exception_code  = 4'd0;
        commit_exception_pc    = 64'd0;
        commit_terminate       = 1'b0;

        flush                  = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head <= '0;
            tail <= '0;

            for (i = 0; i < ROB_SIZE; i = i + 1)
                entries[i] <= '{default: '0, spr_id: SPR_INVALID};
        end else begin
            if (cdb_result.valid) begin
                // Branch completions use value as the resolved next PC, so the
                // ROB only needs the canonical result plus exception/flags state.
                entries[cdb_result.tag].result         <= cdb_result.value;
                entries[cdb_result.tag].flags          <= cdb_result.flags;
                entries[cdb_result.tag].flags_valid    <= cdb_result.flags_valid;
                entries[cdb_result.tag].ready          <= 1'b1;
                entries[cdb_result.tag].exception      <= cdb_result.exception;
                entries[cdb_result.tag].exception_code <= cdb_result.exception_code;
            end

            // allocate rob entry (from rename)
            if (alloc_valid && ready_out) begin
                entries[tail_idx].pc               <= pc_in;
                entries[tail_idx].arch_rd          <= dest_reg;
                entries[tail_idx].rd_valid         <= dest_valid;
                entries[tail_idx].is_branch        <= is_branch_in;
                entries[tail_idx].is_store         <= is_store_in;
                entries[tail_idx].is_eret          <= is_eret_in;
                entries[tail_idx].is_svc           <= is_svc_in;
                entries[tail_idx].is_msr           <= is_msr_in;
                entries[tail_idx].is_mrs           <= is_mrs_in;
                entries[tail_idx].is_privileged    <= is_privileged_in;
                entries[tail_idx].sets_flags       <= sets_flags_in;
                entries[tail_idx].spr_id           <= spr_id_in;
                entries[tail_idx].first_uop        <= first_uop_in;
                entries[tail_idx].last_uop         <= last_uop_in;
                entries[tail_idx].predicted_target <= pred_target;
                entries[tail_idx].predicted_taken  <= pred_taken;
                entries[tail_idx].ready            <= 1'b0;
                entries[tail_idx].result           <= 64'd0;
                entries[tail_idx].flags            <= 4'd0;
                entries[tail_idx].flags_valid      <= 1'b0;
                entries[tail_idx].exception        <= 1'b0;
                entries[tail_idx].exception_code   <= 4'd0;
                entries[tail_idx].valid            <= 1'b1;
                tail                               <= tail + 1'b1;
            end
        end
    end

endmodule

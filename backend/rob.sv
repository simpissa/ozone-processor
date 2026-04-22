`timescale 1ns / 1ps

import frontend_types::*;

module rob #(
    parameter int unsigned ROB_SIZE = (1 << ROB_TAG_W)
) (
    input  logic                 clk,
    input  logic                 rst,

    // Rename -> ROB allocation path
    input  logic                 rob_alloc_valid,
    output logic                 rob_ready,
    output logic [ROB_TAG_W-1:0] rob_tag,
    input  logic [63:0]          rob_pc,
    input  logic [4:0]           rob_dest_reg,
    input  logic                 rob_dest_valid,
    input  logic                 rob_is_branch,
    input  logic                 rob_is_store,
    input  logic                 rob_is_eret,
    input  logic                 rob_is_svc,
    input  logic                 rob_is_msr,
    input  logic                 rob_is_mrs,
    input  logic                 rob_is_privileged,
    input  logic                 rob_sets_flags,
    input  spr_t                 rob_spr_id,
    input  logic                 rob_first_uop,
    input  logic                 rob_last_uop,
    input  logic [63:0]          rob_pred_target,
    input  logic                 rob_pred_taken,

    // Rename lookup ports for completed ROB values
    input  logic                 rob_src1_lookup_valid,
    input  logic [ROB_TAG_W-1:0] rob_src1_lookup_tag,
    output logic                 rob_src1_lookup_hit_ready,
    output logic [63:0]          rob_src1_lookup_value,
    input  logic                 rob_src2_lookup_valid,
    input  logic [ROB_TAG_W-1:0] rob_src2_lookup_tag,
    output logic                 rob_src2_lookup_hit_ready,
    output logic [63:0]          rob_src2_lookup_value,

    // Common data bus broadcast
    input  fu_result_t           cdb_result,

    // Commit information consumed by rename
    output logic                 rob_commit_valid,
    output logic [ROB_TAG_W-1:0] rob_commit_tag,
    output logic [4:0]           rob_commit_dest_reg,
    output logic                 rob_commit_dest_valid,
    output logic [63:0]          rob_commit_value,
    output logic                 rob_commit_sets_flags,
    output logic [63:0]          rob_commit_flags_value,

    // Commit interface
    output logic                 commit_gpr_we,
    output logic [4:0]           commit_gpr_rd,
    output logic [63:0]          commit_gpr_value,
    output logic [ROB_TAG_W-1:0] commit_tag,
    output logic                 commit_spr_we,
    output spr_t                 commit_spr_id,
    output logic [63:0]          commit_spr_value,
    output logic                 commit_store,
    output logic [ROB_TAG_W-1:0] commit_store_tag,
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
    output logic                 rob_full,
    output logic                 rob_empty
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
        logic        exception;
        logic [3:0]  exception_code;
        logic        mispredicted;
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
    assign rob_empty  = (head == tail);
    assign rob_full   = (head[ROB_TAG_W-1:0] == tail[ROB_TAG_W-1:0]) &&
                        (head[ROB_TAG_W] != tail[ROB_TAG_W]);
    assign num_entries = tail - head;

    assign rob_tag   = tail_idx;
    assign rob_ready = !rob_full;

    // rob lookup from rename
    always_comb begin
        rob_src1_lookup_hit_ready = 1'b0;
        rob_src1_lookup_value = 64'd0;
        rob_src2_lookup_hit_ready = 1'b0;
        rob_src2_lookup_value = 64'd0;

        if (rob_src1_lookup_valid) begin
            if (cdb_result.valid && (cdb_result.tag == rob_src1_lookup_tag)) begin
                rob_src1_lookup_hit_ready = 1'b1;
                rob_src1_lookup_value = cdb_result.value;
            end else begin
                rob_src1_lookup_hit_ready = entries[rob_src1_lookup_tag].ready;
                rob_src1_lookup_value = entries[rob_src1_lookup_tag].result;
            end
        end

        if (rob_src2_lookup_valid) begin
            if (cdb_result.valid && (cdb_result.tag == rob_src2_lookup_tag)) begin
                rob_src2_lookup_hit_ready = 1'b1;
                rob_src2_lookup_value = cdb_result.value;
            end else begin
                rob_src2_lookup_hit_ready = entries[rob_src2_lookup_tag].ready;
                rob_src2_lookup_value = entries[rob_src2_lookup_tag].result;
            end
        end
    end

    always_comb begin
        rob_commit_valid       = 1'b0;
        rob_commit_tag         = '0;
        rob_commit_dest_reg    = '0;
        rob_commit_dest_valid  = 1'b0;
        rob_commit_value       = 64'd0;
        rob_commit_sets_flags  = 1'b0;
        rob_commit_flags_value = 64'd0;

        commit_gpr_we          = 1'b0;
        commit_gpr_rd          = '0;
        commit_gpr_value       = 64'd0;
        commit_tag             = '0;
        commit_spr_we          = 1'b0;
        commit_spr_id          = SPR_INVALID;
        commit_spr_value       = 64'd0;
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
        end
    end

endmodule

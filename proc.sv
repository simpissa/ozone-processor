`timescale 1ns / 1ps

import types::*;

module ozone(
    input  logic        clk,
    input  logic        rstN,
    input  logic [63:0] startPC,
    input  logic        start,

    input  logic [511:0] imem_rdata_i,
    input  logic         imem_ready_i,
    input  logic         imem_valid_i,
    output logic         imem_valid_o,
    output logic [29:0]  imem_addr_o,

    input  logic [511:0] itlb_mem_rdata_i,
    input  logic         itlb_mem_ready_i,
    input  logic         itlb_mem_valid_i,
    output logic         itlb_mem_valid_o,
    output logic [29:0]  itlb_mem_addr_o,

    output logic         dmem_load_valid,
    output logic [47:0]  dmem_load_vaddr,
    output logic [ROB_TAG_W-1:0] dmem_load_id,
    input  logic         dmem_load_ready,
    input  logic         dmem_load_received,
    input  logic         dmem_load_resp_valid,
    input  logic [ROB_TAG_W-1:0] dmem_load_resp_id,
    input  logic [63:0]  dmem_load_resp_data,

    output logic         dmem_store_valid,
    output logic [47:0]  dmem_store_vaddr,
    output logic [63:0]  dmem_store_value,
    input  logic         dmem_store_ready,

    output logic         done
);

    logic fe_valid;
    logic fe_ready;
    uop_t fe_uop;
    logic [63:0] fe_pc;
    logic fe_pred_taken;
    logic [63:0] fe_pred_target;

    logic flush;
    logic [63:0] redirect_pc;
    logic terminate;

    logic br_resolve_valid;
    logic br_resolve_is_branch;
    logic br_resolve_is_conditional;
    logic [63:0] br_resolve_pc;
    logic br_resolve_taken;
    logic [63:0] br_resolve_target;
    logic [63:0] ttbr0_el1;
    logic el_out;

    assign done = terminate;

    frontend fe(
        .clk(clk),
        .rstN(rstN && start),
        .startPC(startPC),
        .flush(flush),
        .redirectPC(redirect_pc),
        .ttbr0_el1(ttbr0_el1),
        .el(el_out),
        .imem_rdata_i(imem_rdata_i),
        .imem_ready_i(imem_ready_i),
        .imem_valid_i(imem_valid_i),
        .imem_valid_o(imem_valid_o),
        .imem_addr_o(imem_addr_o),
        .itlb_mem_rdata_i(itlb_mem_rdata_i),
        .itlb_mem_ready_i(itlb_mem_ready_i),
        .itlb_mem_valid_i(itlb_mem_valid_i),
        .itlb_mem_valid_o(itlb_mem_valid_o),
        .itlb_mem_addr_o(itlb_mem_addr_o),
        .valid_out(fe_valid),
        .ready_in(fe_ready),
        .uop_out(fe_uop),
        .pc_out(fe_pc),
        .pred_taken_out(fe_pred_taken),
        .pred_target_out(fe_pred_target),
        .brResolveValid(br_resolve_valid),
        .brResolveIsBranch(br_resolve_is_branch),
        .brResolveIsConditional(br_resolve_is_conditional),
        .brResolvePC(br_resolve_pc),
        .brResolveTaken(br_resolve_taken),
        .brResolveTarget(br_resolve_target)
    );

    core_backend be(
        .clk(clk),
        .rstN(rstN && start),
        .valid_in(fe_valid),
        .ready_out(fe_ready),
        .uop_in(fe_uop),
        .pc_in(fe_pc),
        .pred_taken_in(fe_pred_taken),
        .pred_target_in(fe_pred_target),
        .flush(flush),
        .redirect_pc(redirect_pc),
        .terminate(terminate),
        .brResolveValid(br_resolve_valid),
        .brResolveIsBranch(br_resolve_is_branch),
        .brResolveIsConditional(br_resolve_is_conditional),
        .brResolvePC(br_resolve_pc),
        .brResolveTaken(br_resolve_taken),
        .brResolveTarget(br_resolve_target),
        .ttbr0_el1(ttbr0_el1),
        .el_out(el_out),
        .dmem_load_valid(dmem_load_valid),
        .dmem_load_vaddr(dmem_load_vaddr),
        .dmem_load_id(dmem_load_id),
        .dmem_load_ready(dmem_load_ready),
        .dmem_load_received(dmem_load_received),
        .dmem_load_resp_valid(dmem_load_resp_valid),
        .dmem_load_resp_id(dmem_load_resp_id),
        .dmem_load_resp_data(dmem_load_resp_data),
        .dmem_store_valid(dmem_store_valid),
        .dmem_store_vaddr(dmem_store_vaddr),
        .dmem_store_value(dmem_store_value),
        .dmem_store_ready(dmem_store_ready)
    );

endmodule

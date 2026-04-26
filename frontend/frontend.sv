`timescale 1ns / 1ps

import types::*;

module frontend (
    input  logic        clk,
    input  logic        rstN,
    input  logic [63:0] startPC,

    input  logic        flush,
    input  logic [63:0] redirectPC,

    input  logic [63:0] ttbr0_el1,
    input  logic        el,

    // Instruction cache/line-fill path used by fetch.
    input  logic [511:0] imem_rdata_i,
    input  logic         imem_ready_i,
    input  logic         imem_valid_i,
    output logic         imem_valid_o,
    output logic [29:0]  imem_addr_o,

    // Page-table walk path used by the iTLB.
    input  logic [511:0] itlb_mem_rdata_i,
    input  logic         itlb_mem_ready_i,
    input  logic         itlb_mem_valid_i,
    output logic         itlb_mem_valid_o,
    output logic [29:0]  itlb_mem_addr_o,

    // Decode/rename boundary.
    output logic         valid_out,
    input  logic         ready_in,
    output uop_t         uop_out,
    output logic [63:0]  pc_out,
    output logic         pred_taken_out,
    output logic [63:0]  pred_target_out,

    // Branch resolution feedback for predictor training.
    input logic          brResolveValid,
    input logic          brResolveIsBranch,
    input logic          brResolveIsConditional,
    input logic [63:0]   brResolvePC,
    input logic          brResolveTaken,
    input logic [63:0]   brResolveTarget
);

    logic rst;
    assign rst = !rstN;

    logic [31:0] fetch_instr;
    logic [63:0] fetch_pc;
    logic fetch_valid;
    logic fetch_ready;
    logic fetch_pred_taken;
    logic [63:0] fetch_pred_target;

    logic bp_req_valid;
    logic [63:0] bp_req_pc;
    logic pred_taken;
    logic [63:0] pred_target;

    logic itlb_ready;
    logic itlb_hit;
    logic [29:0] itlb_paddr;
    logic itlb_miss;
    logic [63:0] itlb_vaddr;
    logic itlb_valid;
    logic itlb_mem_valid_raw;
    logic fetch_itlb_ready;
    logic fetch_itlb_hit;
    logic [29:0] fetch_itlb_paddr;
    logic fetch_itlb_miss;

    assign fetch_itlb_ready = el ? 1'b1 : itlb_ready;
    assign fetch_itlb_hit   = el ? itlb_valid : itlb_hit;
    assign fetch_itlb_paddr = el ? itlb_vaddr[29:0] : itlb_paddr;
    assign fetch_itlb_miss  = el ? 1'b0 : itlb_miss;

    assign itlb_mem_valid_o = el ? 1'b0 : itlb_mem_valid_raw;

    assign pc_out = fetch_pc;
    assign pred_taken_out = fetch_pred_taken;
    assign pred_target_out = fetch_pred_target;

    branchPredictor bp (
        .clk(clk),
        .rstN(rstN),
        .predReqValid(bp_req_valid),
        .predReqPC(bp_req_pc),
        .predTaken(pred_taken),
        .predTarget(pred_target),
        .resolveValid(brResolveValid),
        .resolveIsBranch(brResolveIsBranch),
        .resolveIsConditional(brResolveIsConditional),
        .resolvePC(brResolvePC),
        .resolveTaken(brResolveTaken),
        .resolveTarget(brResolveTarget)
    );

    itlb i_itlb (
        .clk(clk),
        .reset(rst),
        .ttbr0(ttbr0_el1),
        .fetch_valid_i(el ? 1'b0 : itlb_valid),
        .fetch_vaddr_i(itlb_vaddr),
        .fetch_hit_o(itlb_hit),
        .fetch_paddr_o(itlb_paddr),
        .fetch_miss_o(itlb_miss),
        .fetch_ready_o(itlb_ready),
        .mem_ready_i(itlb_mem_ready_i),
        .mem_valid_i(itlb_mem_valid_i),
        .mem_rdata_i(itlb_mem_rdata_i),
        .mem_addr_o(itlb_mem_addr_o),
        .mem_valid_o(itlb_mem_valid_raw)
    );

    fetch fetchStage (
        .clk(clk),
        .reset(rst),
        .flush(flush),
        .reset_pc_i(startPC),
        .exe_target_i(redirectPC),
        .dcode_ready_i(fetch_ready),
        .dcode_instr_o(fetch_instr),
        .dcode_pc_o(fetch_pc),
        .dcode_pred_taken_o(fetch_pred_taken),
        .dcode_pred_target_o(fetch_pred_target),
        .dcode_valid_o(fetch_valid),
        .imem_rdata_i(imem_rdata_i),
        .imem_ready_i(imem_ready_i),
        .imem_valid_i(imem_valid_i),
        .imem_valid_o(imem_valid_o),
        .imem_addr_o(imem_addr_o),
        .itlb_ready_i(fetch_itlb_ready),
        .itlb_hit_i(fetch_itlb_hit),
        .itlb_paddr_i(fetch_itlb_paddr),
        .itlb_miss_i(fetch_itlb_miss),
        .itlb_vaddr_o(itlb_vaddr),
        .itlb_valid_o(itlb_valid),
        .bp_taken_i(pred_taken),
        .bp_target_i(pred_target),
        .bp_valid_o(bp_req_valid),
        .bp_vaddr_o(bp_req_pc)
    );

    decoder decoderStage (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .instr(fetch_instr),
        .pc(fetch_pc),
        .valid_in(fetch_valid),
        .ready_out(fetch_ready),
        .valid_out(valid_out),
        .ready_in(ready_in),
        .uop(uop_out)
    );

endmodule

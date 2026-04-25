`timescale 1ns / 1ps

import types::*;

module frontend (
	input logic clk,
	input logic rstN,
	input logic [63:0] ttbr0,

	// Decoder -> backend handshake
	input logic decodeReadyIn,
	output logic decodeValidOut,
	output logic [63:0] decodePCOut,
	output uop_t decodeUop,

	// Fetch instruction memory interface
	input logic [511:0] imemRdata,
	input logic imemReady,
	input logic imemValid,
	output logic imemReqValid,
	output logic [29:0] imemReqAddr,

	// iTLB page-walk memory interface
	input logic [511:0] itlbMemRdata,
	input logic itlbMemReady,
	input logic itlbMemValid,
	output logic itlbMemReqValid,
	output logic [29:0] itlbMemReqAddr,

	// Branch resolution feedback for predictor training
	input logic brResolveValid,
	input logic brResolveIsBranch,
	input logic brResolveIsConditional,
	input logic [63:0] brResolvePC,
	input logic brResolveTaken,
	input logic [63:0] brResolveTarget
);

	logic rst;

	logic decodeReady;
	logic fetchFlush;

	logic predTaken;
	logic [63:0] predTarget;
	logic predReqValid;
	logic [63:0] predReqPC;

	logic [31:0] fetchInstr;
	logic [63:0] fetchPC;
	logic fetchValid;

	logic itlbFetchValid;
	logic [63:0] itlbFetchVaddr;
	logic itlbFetchHit;
	logic [29:0] itlbFetchPaddr;
	logic itlbFetchMiss;
	logic itlbFetchReady;

	assign rst = !rstN;
	assign fetchFlush = brResolveValid && brResolveIsBranch;
	assign decodePCOut = fetchPC;

	branchPredictor bp (
		.clk(clk),
		.rstN(rstN),
		.predReqValid(predReqValid),
		.predReqPC(predReqPC),
		.predTaken(predTaken),
		.predTarget(predTarget),
		.resolveValid(brResolveValid),
		.resolveIsBranch(brResolveIsBranch),
		.resolveIsConditional(brResolveIsConditional),
		.resolvePC(brResolvePC),
		.resolveTaken(brResolveTaken),
		.resolveTarget(brResolveTarget)
	);

	fetch fetchStage (
		.clk(clk),
		.reset(rst),
		.flush(fetchFlush),
		.exe_target_i(brResolveTarget),
		.dcode_ready_i(decodeReady),
		.dcode_instr_o(fetchInstr),
		.dcode_pc_o(fetchPC),
		.dcode_valid_o(fetchValid),
		.imem_rdata_i(imemRdata),
		.imem_ready_i(imemReady),
		.imem_valid_i(imemValid),
		.imem_valid_o(imemReqValid),
		.imem_addr_o(imemReqAddr),
		.itlb_ready_i(itlbFetchReady),
		.itlb_hit_i(itlbFetchHit),
		.itlb_paddr_i(itlbFetchPaddr),
		.itlb_miss_i(itlbFetchMiss),
		.itlb_vaddr_o(itlbFetchVaddr),
		.itlb_valid_o(itlbFetchValid),
		.bp_taken_i(predTaken),
		.bp_target_i(predTarget),
		.bp_valid_o(predReqValid),
		.bp_vaddr_o(predReqPC)
	);

	itlb itlbStage (
		.clk(clk),
		.reset(rst),
		.ttbr0(ttbr0),
		.fetch_valid_i(itlbFetchValid),
		.fetch_vaddr_i(itlbFetchVaddr),
		.fetch_hit_o(itlbFetchHit),
		.fetch_paddr_o(itlbFetchPaddr),
		.fetch_miss_o(itlbFetchMiss),
		.fetch_ready_o(itlbFetchReady),
		.mem_ready_i(itlbMemReady),
		.mem_valid_i(itlbMemValid),
		.mem_rdata_i(itlbMemRdata),
		.mem_addr_o(itlbMemReqAddr),
		.mem_valid_o(itlbMemReqValid)
	);

	decoder decoderStage (
		.clk(clk),
		.rst(rst),
		.flush(fetchFlush),
		.instr(fetchInstr),
		.pc(fetchPC),
		.valid_in(fetchValid),
		.ready_out(decodeReady),
		.valid_out(decodeValidOut),
		.ready_in(decodeReadyIn),
		.uop(decodeUop)
	);

endmodule
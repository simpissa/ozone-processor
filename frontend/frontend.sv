`timescale 1ns / 1ps

import types::*;

module frontend (
	input logic clk,
	input logic rstN,

	// Branch resolution feedback for predictor training.
	input logic brResolveValid,
	input logic brResolveIsBranch,
	input logic brResolveIsConditional,
	input logic [63:0] brResolvePC,
	input logic brResolveTaken,
	input logic [63:0] brResolveTarget
);

	logic rst;

	logic [63:0] fetchNextPC;
	logic decodeReady;

	logic predTaken;
	logic [63:0] predTarget;

	logic [31:0] fetchInstr;
	logic [63:0] fetchPC;
	logic fetchValid;
	logic el;
	logic decodeValidOut;
	logic decodeReadyIn;
	uop_t decodeUop;

	assign rst = !rstN;

	assign decodeReadyIn = 1'b1;

	branchPredictor bp (
		.clk(clk),
		.rstN(rstN),
		.predReqValid(1'b1),
		.predReqPC(fetchNextPC),
		.predTaken(predTaken),
		.predTarget(predTarget),
		.resolveValid(brResolveValid),
		.resolveIsBranch(brResolveIsBranch),
		.resolveIsConditional(brResolveIsConditional),
		.resolvePC(brResolvePC),
		.resolveTaken(brResolveTaken),
		.resolveTarget(brResolveTarget)
	);

	// l1 cache goes here????

	fetch fetchStage (
		.clk(clk),
		.rstN(rstN),
		.predPC(predTarget),
		.decodeReady(decodeReady),
		.nextPC(fetchNextPC),
		.instr(fetchInstr),
		.pc(fetchPC),
		.valid(fetchValid),
		.el(el)
	);

	decoder decoderStage (
		.clk(clk),
		.rst(rst),
		.flush(1'b0),
		.instr(fetchInstr),
		.pc(fetchPC),
		.el(el),
		.valid_in(fetchValid),
		.ready_out(decodeReady),
		.valid_out(decodeValidOut),
		.ready_in(decodeReadyIn),
		.uop(decodeUop)
	);

endmodule
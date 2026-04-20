`timescale 1ns / 1ps

import frontend_types::*;

module backend #(
	parameter int unsigned tagW = 6
) (
	input logic clk,
	input logic rstN,
	input logic flush,

	// Issue input
	input logic issueValid,
	output logic issueReady,
	input fu_t issueFuSelect,
	input fu_op_t issueFuOp,
	input logic [63:0] issueSrc1,
	input logic [63:0] issueSrc2,
	input logic [tagW-1:0] issueTag,

	// Writeback output
	output logic wbValid,
	input logic wbReady,
	output logic [tagW-1:0] wbTag,
	output logic [63:0] wbValue,
	output logic [4:0] wbFflags,
	output logic fpuBusy
);

logic fpuReqValid;
logic fpuReqReady;

assign fpuReqValid = issueValid && (issueFuSelect == FU_FPU);
assign issueReady = (issueFuSelect == FU_FPU) ? fpuReqReady : 1'b0;

fpuExecute #(
	.TAG_W(tagW)
) i_fpu_execute (
	.clk(clk),
	.rstN(rstN),
	.flush(flush),
	.reqValid(fpuReqValid),
	.reqReady(fpuReqReady),
	.reqOp(issueFuOp),
	.reqSrc1(issueSrc1),
	.reqSrc2(issueSrc2),
	.reqTag(issueTag),
	.respValid(wbValid),
	.respReady(wbReady),
	.respTag(wbTag),
	.respResult(wbValue),
	.respFflags(wbFflags),
	.busy(fpuBusy)
);

endmodule
`timescale 1ns / 1ps

import types::*;

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
	input logic issueSrc1Ready,
	input logic [tagW-1:0] issueSrc1Tag,
	input logic [63:0] issueSrc2,
	input logic issueSrc2Ready,
	input logic [tagW-1:0] issueSrc2Tag,
	input logic [tagW-1:0] issueTag,
	input fu_result_t cdbBroadcast,

	// Writeback output
output logic wbValid,
input logic wbReady,
output logic [tagW-1:0] wbTag,
output logic [63:0] wbValue,
output logic [4:0] wbFflags,
output logic wbFlagsValid,
output logic fpuBusy
);

logic fpuReqValid;
logic fpuReqReady;
logic fpuExecValid;
logic fpuExecReady;
fu_op_t fpuExecOp;
logic [63:0] fpuExecSrc1;
logic [63:0] fpuExecSrc2;
logic [tagW-1:0] fpuExecTag;
logic fpuRsBusy;
logic fpuCoreBusy;

assign fpuReqValid = issueValid && (issueFuSelect == FU_FPU);
assign issueReady = (issueFuSelect == FU_FPU) ? fpuReqReady : 1'b0;
assign fpuBusy = fpuRsBusy || fpuCoreBusy;

fpuRs #(
	.RS_ENTRIES(4),
	.TAG_W(tagW)
) fpuRs (
	.clk(clk),
	.rstN(rstN),
	.flush(flush),
	.issueValid(fpuReqValid),
	.issueReady(fpuReqReady),
	.issueOp(issueFuOp),
	.issueSrc1Value(issueSrc1),
	.issueSrc1Ready(issueSrc1Ready),
	.issueSrc1Tag(issueSrc1Tag),
	.issueSrc2Value(issueSrc2),
	.issueSrc2Ready(issueSrc2Ready),
	.issueSrc2Tag(issueSrc2Tag),
	.issueTag(issueTag),
	.cdbIn(cdbBroadcast),
	.execValid(fpuExecValid),
	.execReady(fpuExecReady),
	.execOp(fpuExecOp),
	.execSrc1(fpuExecSrc1),
	.execSrc2(fpuExecSrc2),
	.execTag(fpuExecTag),
	.busy(fpuRsBusy)
);

fpuExecute #(
	.TAG_W(tagW)
) fpuExecute (
	.clk(clk),
	.rstN(rstN),
	.flush(flush),
	.reqValid(fpuExecValid),
	.reqReady(fpuExecReady),
	.reqOp(fpuExecOp),
	.reqSrc1(fpuExecSrc1),
	.reqSrc2(fpuExecSrc2),
	.reqTag(fpuExecTag),
	.respValid(wbValid),
	.respReady(wbReady),
	.respTag(wbTag),
	.respResult(wbValue),
	.respFflags(wbFflags),
	.respFlagsValid(wbFlagsValid),
	.busy(fpuCoreBusy)
);

endmodule

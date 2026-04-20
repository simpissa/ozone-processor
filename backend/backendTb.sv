`timescale 1ns / 1ps

import frontend_types::*;

module backend_tb;
  localparam int unsigned tagW = 6;

  logic clk;
  logic rstN;
  logic flush;

  logic issueValid;
  logic issueReady;
  fu_t issueFuSelect;
  fu_op_t issueFuOp;
  logic [63:0] issueSrc1;
  logic [63:0] issueSrc2;
  logic [tagW-1:0] issueTag;

  logic wbValid;
  logic wbReady;
  logic [tagW-1:0] wbTag;
  logic [63:0] wbValue;
  logic [4:0] wbFflags;
  logic fpuBusy;

  backend #(
    .tagW(tagW)
  ) dut (
    .clk(clk),
    .rstN(rstN),
    .flush(flush),
    .issueValid(issueValid),
    .issueReady(issueReady),
    .issueFuSelect(issueFuSelect),
    .issueFuOp(issueFuOp),
    .issueSrc1(issueSrc1),
    .issueSrc2(issueSrc2),
    .issueTag(issueTag),
    .wbValid(wbValid),
    .wbReady(wbReady),
    .wbTag(wbTag),
    .wbValue(wbValue),
    .wbFflags(wbFflags),
    .fpuBusy(fpuBusy)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic issueFpOp(
    input fu_op_t op,
    input logic [63:0] src1,
    input logic [63:0] src2,
    input logic [tagW-1:0] tag
  );
    begin
      issueFuSelect = FU_FPU;
      issueFuOp = op;
      issueSrc1 = src1;
      issueSrc2 = src2;
      issueTag = tag;
      issueValid = 1'b1;

      while (!issueReady) @(posedge clk);
      @(posedge clk);
      issueValid = 1'b0;
    end
  endtask

  task automatic waitWbAndCheckTag(
    input logic [tagW-1:0] expTag
  );
    begin
      while (!wbValid) @(posedge clk);
      if (wbTag !== expTag) begin
        $error("Writeback tag mismatch. expected=%0d got=%0d", expTag, wbTag);
        $fatal(1);
      end
    end
  endtask

  initial begin
    rstN = 1'b0;
    flush = 1'b0;
    wbReady = 1'b1;
    issueValid = 1'b0;
    issueFuSelect = FU_NONE;
    issueFuOp = OP_NOP;
    issueSrc1 = 64'd0;
    issueSrc2 = 64'd0;
    issueTag = '0;

    repeat (5) @(posedge clk);
    rstN = 1'b1;
    repeat (2) @(posedge clk);

    // 1.5 + 2.25 = 3.75
    issueFpOp(OP_FADD, 64'h3FF8_0000_0000_0000, 64'h4002_0000_0000_0000, 6'd3);
    waitWbAndCheckTag(6'd3);
    if (wbValue !== 64'h400E_0000_0000_0000) begin
      $error("FADD result mismatch. expected=0x%016h got=0x%016h", 64'h400E_0000_0000_0000, wbValue);
      $fatal(1);
    end

    // 2.0 * 4.0 = 8.0
    issueFpOp(OP_FMUL, 64'h4000_0000_0000_0000, 64'h4010_0000_0000_0000, 6'd7);
    waitWbAndCheckTag(6'd7);
    if (wbValue !== 64'h4020_0000_0000_0000) begin
      $error("FMUL result mismatch. expected=0x%016h got=0x%016h", 64'h4020_0000_0000_0000, wbValue);
      $fatal(1);
    end

    // Compare: 3.0 <= 2.0 should be false (0)
    issueFpOp(OP_FCMP, 64'h4008_0000_0000_0000, 64'h4000_0000_0000_0000, 6'd11);
    waitWbAndCheckTag(6'd11);
    if (wbValue[0] !== 1'b0) begin
      $error("FCMP result mismatch. expected LSB=0 got=0x%016h", wbValue);
      $fatal(1);
    end

    $display("backend_tb: PASS");
    $finish;
  end
endmodule
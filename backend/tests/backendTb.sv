`timescale 1ns / 1ps

import types::*;


module backendTb;
  localparam int unsigned tagW = 6;

  logic clk;
  logic rstN;
  logic flush;

  logic issueValid;
  logic issueReady;
  fu_t issueFuSelect;
  fu_op_t issueFuOp;
  logic [63:0] issueSrc1;
  logic issueSrc1Ready;
  logic [tagW-1:0] issueSrc1Tag;
  logic [63:0] issueSrc2;
  logic issueSrc2Ready;
  logic [tagW-1:0] issueSrc2Tag;
  logic [tagW-1:0] issueTag;
  fu_result_t cdbBroadcast;

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
    .issueSrc1Ready(issueSrc1Ready),
    .issueSrc1Tag(issueSrc1Tag),
    .issueSrc2(issueSrc2),
    .issueSrc2Ready(issueSrc2Ready),
    .issueSrc2Tag(issueSrc2Tag),
    .issueTag(issueTag),
    .cdbBroadcast(cdbBroadcast),
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

  task automatic waitWb(input logic [tagW-1:0] expTag, input logic [63:0] expValue);
    int i;
    begin
      for (i = 0; i < 40; i = i + 1) begin
        @(posedge clk);
        if (wbValid && wbReady) begin
          if (wbTag !== expTag) begin
            $fatal(1, "Writeback tag mismatch exp=%0d got=%0d", expTag, wbTag);
          end
          if (wbValue !== expValue) begin
            $fatal(1, "Writeback value mismatch exp=%h got=%h", expValue, wbValue);
          end
          return;
        end
      end
      $fatal(1, "Timed out waiting for writeback");
    end
  endtask

  initial begin
    rstN = 1'b0;
    flush = 1'b0;
    issueValid = 1'b0;
    issueFuSelect = FU_NONE;
    issueFuOp = OP_NOP;
    issueSrc1 = '0;
    issueSrc1Ready = 1'b1;
    issueSrc1Tag = '0;
    issueSrc2 = '0;
    issueSrc2Ready = 1'b1;
    issueSrc2Tag = '0;
    issueTag = '0;
    cdbBroadcast = '0;
    wbReady = 1'b1;

    repeat (4) @(posedge clk);
    rstN = 1'b1;
    repeat (2) @(posedge clk);

    // Non-FPU issue should not be accepted by backend.sv
    issueFuSelect = FU_ALU;
    issueFuOp = OP_ADD;
    issueSrc1 = 64'd1;
    issueSrc2 = 64'd2;
    issueTag = 6'd1;
    issueValid = 1'b1;
    @(posedge clk);
    if (issueReady !== 1'b0) begin
      $fatal(1, "Expected issueReady=0 for non-FPU issue");
    end
    issueValid = 1'b0;

    // FPU FADD path should handshake and write back deterministic stub result
    issueFuSelect = FU_FPU;
    issueFuOp = OP_FADD;
    issueSrc1 = 64'd10;
    issueSrc2 = 64'd5;
    issueTag = 6'd3;
    issueValid = 1'b1;
    while (!issueReady) @(posedge clk);
    @(posedge clk);
    issueValid = 1'b0;
    waitWb(6'd3, 64'd15);

    // Backpressure on wbReady should hold wbValid until sink is ready
    wbReady = 1'b0;
    issueFuSelect = FU_FPU;
    issueFuOp = OP_FMUL;
    issueSrc1 = 64'd3;
    issueSrc2 = 64'd7;
    issueTag = 6'd4;
    issueValid = 1'b1;
    while (!issueReady) @(posedge clk);
    @(posedge clk);
    issueValid = 1'b0;

    repeat (3) @(posedge clk);
    if (!wbValid) begin
      $fatal(1, "Expected wbValid to remain asserted while wbReady=0");
    end

    wbReady = 1'b1;
    // If an older response is draining first, wait it out before checking
    //   the second issued op's response
    if (wbValid && (wbTag != 6'd4)) begin
      @(posedge clk);
    end
    waitWb(6'd4, 64'd21);

    // Flush clears in-flight state and busy
    issueFuSelect = FU_FPU;
    issueFuOp = OP_FADD;
    issueSrc1 = 64'd2;
    issueSrc2 = 64'd2;
    issueTag = 6'd5;
    issueValid = 1'b1;
    while (!issueReady) @(posedge clk);
    @(posedge clk);
    issueValid = 1'b0;

    flush = 1'b1;
    @(posedge clk);
    flush = 1'b0;
    @(posedge clk);

    if (fpuBusy) begin
      $fatal(1, "Expected fpuBusy=0 after flush");
    end

    $display("backendTb: all tests passed");
    $finish;
  end

endmodule
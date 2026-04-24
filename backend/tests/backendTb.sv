`timescale 1ns / 1ps

import types::*;

module backend_tb;
  localparam int unsigned tagW = 6;

  function automatic string fuOpName(input fu_op_t op);
    case (op)
      OP_NOP:       return "OP_NOP";
      OP_FADD:      return "OP_FADD";
      OP_FMUL:      return "OP_FMUL";
      OP_FCMP:      return "OP_FCMP";
      OP_NAN_CHECK: return "OP_NAN_CHECK";
      default:      return "OP_UNKNOWN";
    endcase
  endfunction

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

  always @(posedge clk) begin
    if (issueValid && issueReady) begin
      $display("[%0t] ISSUE accepted op=%s tag=%0d src1Ready=%0b src2Ready=%0b src1=0x%016h src2=0x%016h",
               $time, fuOpName(issueFuOp), issueTag, issueSrc1Ready, issueSrc2Ready, issueSrc1, issueSrc2);
    end
    if (cdbBroadcast.valid) begin
      $display("[%0t] CDB broadcast tag=%0d value=0x%016h", $time, cdbBroadcast.tag, cdbBroadcast.value);
    end
    if (wbValid && wbReady) begin
      $display("[%0t] WRITEBACK tag=%0d value=0x%016h fflags=0x%0h", $time, wbTag, wbValue, wbFflags);
    end
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
      issueSrc1Ready = 1'b1;
      issueSrc1Tag = '0;
      issueSrc2 = src2;
      issueSrc2Ready = 1'b1;
      issueSrc2Tag = '0;
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
    $display("backend_tb: starting test sequence");

    rstN = 1'b0;
    flush = 1'b0;
    cdbBroadcast = '0;
    wbReady = 1'b1;
    issueValid = 1'b0;
    issueFuSelect = FU_NONE;
    issueFuOp = OP_NOP;
    issueSrc1 = 64'd0;
    issueSrc1Ready = 1'b0;
    issueSrc1Tag = '0;
    issueSrc2 = 64'd0;
    issueSrc2Ready = 1'b0;
    issueSrc2Tag = '0;
    issueTag = '0;

    repeat (5) @(posedge clk);
    rstN = 1'b1;
    $display("[%0t] Reset deasserted", $time);
    repeat (2) @(posedge clk);

    // 1.5 + 2.25 = 3.75
    $display("backend_tb: test OP_FADD (1.5 + 2.25)");
    issueFpOp(OP_FADD, 64'h3FF8_0000_0000_0000, 64'h4002_0000_0000_0000, 6'd3);
    waitWbAndCheckTag(6'd3);
    if (wbValue !== 64'h400E_0000_0000_0000) begin
      $error("FADD result mismatch. expected=0x%016h got=0x%016h", 64'h400E_0000_0000_0000, wbValue);
      $fatal(1);
    end

    // 2.0 * 4.0 = 8.0
    $display("backend_tb: test OP_FMUL (2.0 * 4.0)");
    issueFpOp(OP_FMUL, 64'h4000_0000_0000_0000, 64'h4010_0000_0000_0000, 6'd7);
    waitWbAndCheckTag(6'd7);
    if (wbValue !== 64'h4020_0000_0000_0000) begin
      $error("FMUL result mismatch. expected=0x%016h got=0x%016h", 64'h4020_0000_0000_0000, wbValue);
      $fatal(1);
    end

    // Compare: 3.0 <= 2.0 should be false (0)
    $display("backend_tb: test OP_FCMP (3.0 <= 2.0)");
    issueFpOp(OP_FCMP, 64'h4008_0000_0000_0000, 64'h4000_0000_0000_0000, 6'd11);
    waitWbAndCheckTag(6'd11);
    if (wbValue[0] !== 1'b0) begin
      $error("FCMP result mismatch. expected LSB=0 got=0x%016h", wbValue);
      $fatal(1);
    end

    // Dependency wakeup through CDB: src1 waits on tag 21, src2 is ready (2.0)
    $display("backend_tb: test CDB dependency wakeup");
    issueFuSelect = FU_FPU;
    issueFuOp = OP_FADD;
    issueSrc1 = 64'd0;
    issueSrc1Ready = 1'b0;
    issueSrc1Tag = 6'd21;
    issueSrc2 = 64'h4000_0000_0000_0000;
    issueSrc2Ready = 1'b1;
    issueSrc2Tag = '0;
    issueTag = 6'd12;
    issueValid = 1'b1;
    while (!issueReady) @(posedge clk);
    @(posedge clk);
    issueValid = 1'b0;

    // Broadcast producer result (1.5) on the CDB to wake waiting src1.
    cdbBroadcast.valid = 1'b1;
    cdbBroadcast.tag = 6'd21;
    cdbBroadcast.value = 64'h3FF8_0000_0000_0000;
    cdbBroadcast.flags = 4'd0;
    cdbBroadcast.flags_valid = 1'b0;
    cdbBroadcast.exception = 1'b0;
    cdbBroadcast.exception_code = 4'd0;
    @(posedge clk);
    cdbBroadcast = '0;

    waitWbAndCheckTag(6'd12);
    if (wbValue !== 64'h400C_0000_0000_0000) begin
      $error("FADD CDB wakeup mismatch. expected=0x%016h got=0x%016h", 64'h400C_0000_0000_0000, wbValue);
      $fatal(1);
    end

    $display("backend_tb: PASS");
    $finish;
  end
endmodule
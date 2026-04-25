`timescale 1ns / 1ps
import types::*;

module fpuExecTb #(
  parameter int TAG_LEN = 6
) ();
  logic clk;
  logic rstN;
  logic flush;

  logic reqValid;
  logic reqReady;
  fu_op_t reqOp;
  logic [63:0] reqSrc1;
  logic [63:0] reqSrc2;
  logic [TAG_LEN-1:0] reqTag;

  logic respValid;
  logic respReady;
  logic [TAG_LEN-1:0] respTag;
  logic [63:0] respResult;
  logic [4:0] respFflags;
  logic busy;

  fpuExecute #(.TAG_W(TAG_LEN)) fpu_execute (
    .clk(clk),
    .rstN(rstN),
    .flush(flush),
    .reqValid(reqValid),
    .reqReady(reqReady),
    .reqOp(reqOp),
    .reqSrc1(reqSrc1),
    .reqSrc2(reqSrc2),
    .reqTag(reqTag),
    .respValid(respValid),
    .respReady(respReady),
    .respTag(respTag),
    .respResult(respResult),
    .respFflags(respFflags),
    .busy(busy)
  );

  reg [140:0] trace_line;
  integer fd;

  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  initial begin
    fd = $fopen("output.txt", "r");

    reqValid = 0;
    reqOp = OP_NOP;
    reqSrc1 = 64'd0;
    reqSrc2 = 64'd0;
    reqTag = '0;
    respReady = 1'b1;

    flush = 1'b0;
    rstN = 1'b0;
    @(posedge clk);
    @(posedge clk);
    rstN = 1'b1;

    while (!$feof(fd)) begin : test_loop
      $fscanf(fd, "%b\n", trace_line);
      @(negedge clk);
      {reqValid, reqOp, reqSrc1, reqSrc2, reqTag, respReady} = trace_line;
      @(posedge clk);
      $display(
        "reqV:%b reqR:%b op:%0d tag:%0d | respV:%b respTag:%0d result:%h fflags:%b busy:%b",
        reqValid,
        reqReady,
        reqOp,
        reqTag,
        respValid,
        respTag,
        respResult,
        respFflags,
        busy
      );
    end : test_loop

    repeat (12) begin
      @(negedge clk);
      reqValid = 1'b0;
      reqOp = OP_NOP;
      reqSrc1 = 64'd0;
      reqSrc2 = 64'd0;
      reqTag = '0;
      respReady = 1'b1;
      @(posedge clk);
      $display(
        "drain | respV:%b respTag:%0d result:%h fflags:%b busy:%b",
        respValid,
        respTag,
        respResult,
        respFflags,
        busy
      );
    end

    $fclose(fd);
    $finish;
  end

endmodule : fpuExecTb
`default_nettype wire
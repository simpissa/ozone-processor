`timescale 1ns / 1ps

import types::*;


module frontendTb();

logic clk;
logic rstN;

logic [63:0] ttbr0;
logic decodeReadyIn;
logic decodeValidOut;
logic [63:0] decodePCOut;
uop_t decodeUop;

logic [511:0] imemRdata;
logic imemReady;
logic imemValid;
logic imemReqValid;
logic [29:0] imemReqAddr;

logic [511:0] itlbMemRdata;
logic itlbMemReady;
logic itlbMemValid;
logic itlbMemReqValid;
logic [29:0] itlbMemReqAddr;

logic brResolveValid;
logic brResolveIsBranch;
logic brResolveIsConditional;
logic [63:0] brResolvePC;
logic brResolveTaken;
logic [63:0] brResolveTarget;

frontend dut (
  .clk(clk),
  .rstN(rstN),
  .ttbr0(ttbr0),
  .decodeReadyIn(decodeReadyIn),
  .decodeValidOut(decodeValidOut),
  .decodePCOut(decodePCOut),
  .decodeUop(decodeUop),
  .imemRdata(imemRdata),
  .imemReady(imemReady),
  .imemValid(imemValid),
  .imemReqValid(imemReqValid),
  .imemReqAddr(imemReqAddr),
  .itlbMemRdata(itlbMemRdata),
  .itlbMemReady(itlbMemReady),
  .itlbMemValid(itlbMemValid),
  .itlbMemReqValid(itlbMemReqValid),
  .itlbMemReqAddr(itlbMemReqAddr),
  .brResolveValid(brResolveValid),
  .brResolveIsBranch(brResolveIsBranch),
  .brResolveIsConditional(brResolveIsConditional),
  .brResolvePC(brResolvePC),
  .brResolveTaken(brResolveTaken),
  .brResolveTarget(brResolveTarget)
);

function automatic [511:0] makeImemLine(input logic [31:0] word0, input logic [31:0] word1);
  logic [511:0] line;
  begin
    line = '0;
    line[31:0] = word0;
    line[63:32] = word1;
    makeImemLine = line;
  end
endfunction

task automatic waitCycles(input int n);
  int i;
  begin
    for (i = 0; i < n; i = i + 1) begin
      @(negedge clk);
    end
  end
endtask

task automatic initFetchPipelineState();
  begin
    // Fetch has no explicit reset on these stage flops; seed them from TB.
    dut.fetchStage.stage2.valid = 1'b0;
    dut.fetchStage.stage2.vaddr = '0;
    dut.fetchStage.stage2.paddr = '0;

    dut.fetchStage.stage3.valid = 1'b0;
    dut.fetchStage.stage3.vaddr = '0;
    dut.fetchStage.stage3.paddr = '0;
    dut.fetchStage.stage3.instr = '0;

    dut.fetchStage.stage4.valid = 1'b0;
    dut.fetchStage.stage4.vaddr = '0;
    dut.fetchStage.stage4.paddr = '0;
    dut.fetchStage.stage4.instr = '0;

    dut.fetchStage.imem_addr_o = '0;
    dut.fetchStage.imem_valid_o = 1'b0;
    dut.fetchStage.itlb_valid_o = 1'b0;
    dut.fetchStage.itlb_vaddr_o = '0;
  end
endtask

initial begin
  clk = 1'b0;
  forever #5 clk = ~clk;
end

initial begin
  rstN = 1'b0;
  ttbr0 = 64'd0;
  decodeReadyIn = 1'b1;

  imemRdata = makeImemLine(32'hd503201f, 32'hd503201f);
  imemReady = 1'b1;
  imemValid = 1'b1;

  itlbMemRdata = '0;
  itlbMemReady = 1'b1;
  itlbMemValid = 1'b0;

  brResolveValid = 1'b0;
  brResolveIsBranch = 1'b0;
  brResolveIsConditional = 1'b0;
  brResolvePC = 64'd0;
  brResolveTaken = 1'b0;
  brResolveTarget = 64'd0;

  repeat (3) @(negedge clk);
  rstN = 1'b1;

  // Fetch does not consume reset directly, so drive the architected
  //   frontend flush path once to initialize its pipeline and force PC=0
  @(negedge clk);
  brResolveValid = 1'b1;
  brResolveIsBranch = 1'b1;
  brResolveIsConditional = 1'b0;
  brResolvePC = 64'd0;
  brResolveTaken = 1'b1;
  brResolveTarget = 64'd0;

  @(negedge clk);
  brResolveValid = 1'b0;
  brResolveIsBranch = 1'b0;
  brResolveTaken = 1'b0;

  initFetchPipelineState();
  @(negedge clk);

  // Test 1: after reset redirect, fetch PC should be active and aligned
  waitCycles(2);
  if (dut.fetchStage.pc[1:0] != 2'b00) begin
    $fatal(1, "Expected 4-byte aligned fetch PC, got %h", dut.fetchStage.pc);
  end
  if (dut.fetchStage.pc < 64'd4) begin
    $fatal(1, "Expected fetch PC to advance after startup redirect, got %h", dut.fetchStage.pc);
  end

  // Test 2: branch resolution flush redirects fetch stream
  @(negedge clk);
  brResolveValid = 1'b1;
  brResolveIsBranch = 1'b1;
  brResolveIsConditional = 1'b0;
  brResolvePC = 64'd4;
  brResolveTaken = 1'b1;
  brResolveTarget = 64'h80;

  @(negedge clk);
  brResolveValid = 1'b0;
  brResolveIsBranch = 1'b0;
  brResolveTaken = 1'b0;

  waitCycles(2);
  if (dut.fetchStage.pc[1:0] != 2'b00) begin
    $fatal(1, "Expected aligned fetch PC after redirect, got %h", dut.fetchStage.pc);
  end
  if (dut.fetchStage.pc < 64'h80) begin
    $fatal(1, "Expected fetch PC to redirect toward target >= 0x80, got %h", dut.fetchStage.pc);
  end

  // Test 3: iTLB walk channel remains idle under the iTLB hit stub
  if (itlbMemReqValid) begin
    $fatal(1, "Unexpected iTLB memory walk request under hit-only stub");
  end

  // fetch keeps issuing iTLB lookups and instruction requests
  if (!dut.fetchStage.itlb_valid_o) begin
    $fatal(1, "Expected fetch to drive iTLB lookup valid");
  end
  if (!imemReqValid) begin
    $fatal(1, "Expected fetch to drive instruction memory requests");
  end

  $display("frontendTb: all tests passed");
  $finish();
end

endmodule
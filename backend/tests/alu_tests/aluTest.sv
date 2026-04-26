`timescale 1ns / 1ps

module test();
localparam int unsigned TAG_LEN = 6;
logic clk;
logic rstN;
logic flush;

// input
logic valid_in;
logic ready_out;
logic [63:0] arg1;
logic [63:0] arg2;
logic [TAG_LEN-1:0] tag;
logic [TAG_LEN-1:0] flag_tag;
logic should_output;
logic set_flags;
fu_op_t op;

logic valid_out;
logic ready_in;
fu_result_t result;

alu #() dut (
  .clk(clk),
  .rstN(rstN),
  .flush(flush),
  .valid_in(valid_in),
  .ready_out(ready_out),
  .arg1(arg1),
  .arg2(arg2),
  .tag(tag),
  .flag_tag(flag_tag),
  .should_output(should_output),
  .set_flags(set_flags),
  .op(op),
  .valid_out(valid_out),
  .ready_in(ready_in),
  .result(result)
);

alu_rs #() res_stations(
  .clk(),
	.rstN(),
	.flush(),
	.issueValid(),
	.issueReady(),
  .payload_bus(),
  .cdb_out(),
  .valid_out(),
  .ready_in(),
  .arg1(),
  .arg2(),
  .tag(),
  .flag_tag(),
  .should_output(),
  .set_flags(),
   .op()
);
  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  logic dbg = 1;

  task print_alu;
    #1; 

    if (dbg) begin
        $display("<----------------------------------- ALU PINS ---------------------------------->");
        $display("| %-6s | %-5s | %-5s | %-9s | %-7s | %-10s | %-9s | %-7s | %-11s | ", "RDY_IN", "OUT_V", "RES_V", "RES_TAG", "RES_VAL", "RES_FLGS", "RES_FLG_V", "RES_EXC", "RES_EXC_CD");
        $display("| %-6b | %-5b | %-5d | 0x%-7x | %-7d | 0x%-8x | %-9b | %-7b | %-11b |", ready_out, valid_out, result.valid, result.tag, result.value, result.flags, result.flags_valid, result.exception, result.exception_code);
        $display("|-----------------------------------------------------------------------------------------|\n");
    end
  endtask

  task reset_test_state;
    
    clk = 0;
    rstN = 1;
    flush = 0;

    valid_in = 0;
    arg1 = 0;
    arg2 = 0;
    tag = 0;
    flag_tag = 0;
    should_output = 0;
    set_flags = 0;
    op = OP_ADD;
    ready_in = 0;
    
    rstN = 0;
    @(negedge clk);
    rstN = 1;
    @(negedge clk);

  endtask;

// Tests to see if it successfully waits for l2 to accept data
task test1;
  @(negedge clk);

  $display("\nBeginning alu unit tests");
  $display("Testing basic in and out\n");

  $display("Initial state");
  print_alu();

  @(negedge clk);

  $display("Present nothing");
  valid_in = 1'b0;
    
  print_alu(); // Print result
  @(negedge clk); // Continue

  $display("Present 2 vals");
  valid_in = 1'b1;
  arg1 = 20;
  arg2 = 15;
  tag = 1;
  flag_tag = 0;
  should_output = 1'b1;
  set_flags = 0;
  op = OP_ADD;
  ready_in = 0;
    
  print_alu(); // Print result
  @(negedge clk); // Continue
  
  $display("Switch input while waiting for out");
  valid_in = 1'b1;
  arg1 = 15;
  arg2 = 5;
  tag = 2;
  flag_tag = 0;
  should_output = 1'b1;
  set_flags = 0;
  op = OP_ADD;
  ready_in = 1;
  print_alu(); // Print result
  @(negedge clk);

  print_alu(); // Print result
  @(negedge clk);
  print_alu(); // Print result
  @(negedge clk);
  print_alu(); // Print result
  
    
  $display("Test I passed");
  reset_test_state();
endtask

// task test2();
// endtask

// task test3();
//     $display("Test III passed");
//     reset_test_state();
// endtask

initial begin
  reset_test_state();
    test1();
    // test2();
    // test3();

    $finish();
end

endmodule

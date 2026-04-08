`timescale 1ns / 1ps

module test();

logic clk;
logic reset;

logic [47:0] load_vaddr;
logic [47:0] store_vaddr;
logic loadValid;
logic [3:0] load_id;
logic [3:0] store_id;
logic storeValid;
logic [63:0] store_data;
logic [3:0] load_id_completed;
logic [3:0] store_id_completed;
logic store_finished;
logic load_finished;
logic load_received;
logic store_received;

logic l1ready;
logic [63:0] data_out;
logic data_valid;

logic l2_req_valid;
logic l2_req_rw;
logic [23:0] l2_req_paddr;

logic [63:0] l2_req_data;
logic [3:0] l2_query_id;
logic l2_evict_valid;
logic [511:0] l2_evict_data;
logic l2_ready_for_req;

logic l2_resp_valid;
logic [511:0] l2_resp_data;
logic [3:0] l2_resp_id;
logic [23:0] l2_paddr;

logic [29:0] tlb_paddr_in;
logic tlb_paddr_ready;
logic [47:0] tlb_vaddr_out;
logic tlb_vaddr_valid;

l1cache #() dut (
    .clk(clk),
    .reset(reset),
    .load_vaddr(load_vaddr),
    .store_vaddr(store_vaddr),
    .loadValid(loadValid),
    .load_id(load_id),
    .store_id(store_id),
    .storeValid(storeValid),
    .store_data(store_data),
    .load_id_completed(load_id_completed),
    .store_id_completed(store_id_completed),
    .store_finished(store_finished),
    .load_finished(load_finished),
    .load_received(load_received),
    .store_received(store_received),
    .l1ready(l1ready),
    .data_out(data_out),
    .data_valid(data_valid),
    .l2_req_valid(l2_req_valid),
    .l2_req_rw(l2_req_rw),
    .l2_req_paddr(l2_req_paddr),
    .l2_req_data(l2_req_data),
    .l2_query_id(l2_query_id),
    .l2_evict_valid(l2_evict_valid),
    .l2_evict_data(l2_evict_data),
    .l2_ready_for_req(l2_ready_for_req),
    .l2_resp_valid(l2_resp_valid),
    .l2_resp_data(l2_resp_data),
    .l2_resp_id(l2_resp_id),
    .l2_paddr(l2_paddr),
    .tlb_paddr_in(tlb_paddr_in),
    .tlb_paddr_ready(tlb_paddr_ready),
    .tlb_vaddr_out(tlb_vaddr_out),
    .tlb_vaddr_valid(tlb_vaddr_valid)
);
	localparam int VADDR_W = 48;
  localparam int PADDR_W = 30;
  localparam int BLOCK_SIZE = 64;
  localparam int NUM_WAYS = 2;
  localparam int CAPACITY = 512;
  localparam int NUM_MSHRS = 2;
  localparam int MSHR_QUEUE_SIZE = 4;
  localparam int ID_LENGTH = 4;


  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

  logic dbg = 1;

  task print_cache;
    #1; 

    if (dbg) begin
        $display("<----------------------------------- CACHE PINS IN ---------------------------------->");
        $display("| %-4s | %-4s | %-5s | %-5s | %-14s | %-14s | %-18s |", "ST_V", "LD_V", "ST_ID", "LD_ID", "ST_ADDR", "LD_ADDR", "ST_DATA");
        $display("| %-4b | %-4b | %-5d | %-5d | 0x%-12x | 0x%-12x | 0x%-16x |", storeValid, loadValid, store_id, load_id, store_vaddr, load_vaddr, store_data);
        $display("| %-5s | %-14s | %-16s |", "TLB_V", "TLB_ADDR", "TLB_ADDR_HIGH_BITS");
        $display("| %-5b | 0x%-12x | 0x%-14x |", tlb_paddr_ready, tlb_paddr_in, tlb_paddr_in[PADDR_W-1:$clog2(BLOCK_SIZE)]);

        $display("<----------- LSQ PINS OUT ----------->");
        $display("| %-3s | %-4s | %-4s | %-5s | %-5s |", "RDY", "ST_D", "LD_D", "ST_ID", "LD_ID");
        $display("| %-3b | %-4b | %-4b | %-5d | %-5d |", l1ready, store_finished, load_finished, store_id_completed, load_id_completed);

        $display("<------ TLB PINS OUT ----->");
        $display("| %-6s | %-14s |", "ADDR_V", "ADDR");
        $display("| %-6b | 0x%-12x |", tlb_vaddr_valid, tlb_vaddr_out);

        $display("<----------------------- L2 PINS OUT ----------------------->");
        $display("| %-5s | %-6s | %-10s | %-18s | %-6s |", "REQ_V", "REQ_ST", "REQ_ADDR", "REQ_DATA", "REQ_ID");
        $display("| %-5b | %-6b | 0x%-8x | 0x%-16x | %-6d |", l2_req_valid, l2_req_rw, l2_req_paddr, l2_req_data, l2_query_id);
        $display("|-----------------------------------------------------------------------------------------|\n");
    end
  endtask

  task reset_test_state;
    
    // set every l1 input back to 0
    load_vaddr = 0;
    store_vaddr = 0;
    loadValid = 0;
    load_id = '0;
    store_id = '0;
    storeValid = 0;
    store_data = '0;
    l2_ready_for_req = 0;
    l2_resp_valid = 0;
    l2_resp_data = '0;
    l2_paddr = '0;
    l2_resp_id = '0;

    tlb_paddr_in = '0;
    tlb_paddr_ready = 0;
    
    reset = 1;
    @(negedge clk);
    reset = 0;
    @(negedge clk);

  endtask;

// Tests to see if it successfully waits for l2 to accept data
task test1;
  @(negedge clk);

  $display("\nBeginning l1 unit tests");
  $display("Testing pipeline miss propogation\n");

  $display("Initial state");
  print_cache();

  @(negedge clk);

  $display("Present load at 0x1FFFFFFFFFFF. Should have tlb addr out");
  loadValid = 1'b1;
  load_id = 1;
  load_vaddr = 48'h1FFFFFFFFFFF;
    
    #1  
    assert(tlb_vaddr_valid);
    assert(tlb_vaddr_out == 48'h1FFFFFFFFFFF);
    assert(load_received);

    

  print_cache();

  @(negedge clk);

  $display("Second stage, should have the tlb data returned");
  loadValid = 1'b0;
  tlb_paddr_ready = 1'b1;
  tlb_paddr_in = 30'h0FFFFFFF;

  #1
  print_cache();

  @(negedge clk);
  $display("Third stage, should have output for l2 miss");
  tlb_paddr_ready = 1'b0;

  #1
  print_cache();

  @(negedge clk);
  $display("Should persist its stage since l2 cant accept");

  #1
  print_cache();

  @(negedge clk);
  $display("\nSay l2 accepts\n");
  l2_ready_for_req = 1'b1;

  print_cache();
  assert(l2_req_valid);
  assert(l2_req_paddr == tlb_paddr_in[29:6]);

  @(negedge clk);
  l2_ready_for_req = 0;
  print_cache();
  @(negedge clk);
  $display("\nCheck if mshr stops outputting value after\n");
  l2_ready_for_req = 1;
  print_cache();
  assert(l2_req_valid == 0);
    
  $display("Test I passed");
  reset_test_state();
endtask

task test2();
    $display("\n\n\n\nTest II: Test pipeline with tlb+a stall");
    print_cache();

    assert(l1ready);
    $display("L1 ready, provide load");
    loadValid = 1'b1;
    load_vaddr = 48'hfef3fff323e;
    load_id = 4'd3;
    print_cache();
    assert(tlb_vaddr_valid);
    assert(tlb_vaddr_out == load_vaddr);
    
    @(negedge clk);

    $display("\nLoad taken, disable load input, no tlb given yet\n");
    loadValid = 0;
    print_cache();
    assert(~tlb_vaddr_valid);

    @(negedge clk);

    $display("\nProvide tlb response, should be doing stage 2, pipelining stage 3\n");
    tlb_paddr_in = 30'h329034fe;
    tlb_paddr_ready = 1;
    print_cache();

    @(negedge clk);

    $display("\nAddress should be in stage 3 asking for l2\n");
    $display("Wanted l2 addr: %x", tlb_paddr_in[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    tlb_paddr_ready = 0;
    l2_ready_for_req = 1;
    print_cache();
    assert(l2_req_valid);
    assert(!l2_req_rw);
    // assert(l2_req_paddr == tlb_paddr_in[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    assert(l2_query_id == load_id);
    assert(!l2_evict_valid);

    @(negedge clk);

    print_cache();

    assert(l2_req_valid);
    assert(!l2_req_rw);
    // assert(l2_req_paddr == tlb_paddr_in[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    assert(l2_query_id == 4'd3);
    assert(!l2_evict_valid);
    
    $display("Test II passed");
    reset_test_state();
endtask

// Get loads in all 3 stages, stall l2 with tlb miss
// See if l2 resumes normally
logic[PADDR_W-1:0] addrStart1;
logic[PADDR_W-1:0] addrStart2;
task test3();
    $display("\n\n\n\nTest III: Test whole cache pipeline");
    print_cache();

    @(negedge clk);

    assert(l1ready);
    $display("\nL1 ready, provide load, tlb should request\n");
    loadValid = 1'b1;
    load_vaddr = 48'hfef3fff323e;
    load_id = 4'd1;
    print_cache();
    assert(tlb_vaddr_valid);
    assert(tlb_vaddr_out == load_vaddr);

    @(negedge clk);

    $display("\nWork stage2 and take another load, provide tlb\n");
    loadValid = 1'b1;
    load_vaddr = 48'h1FFFFFFFFFFF;
    load_id = 4'd2;
    tlb_paddr_in = 30'h329034fe;
    addrStart1 = tlb_paddr_in;
    tlb_paddr_ready = 1'b1;
    print_cache();
    assert(tlb_vaddr_valid);
    assert(tlb_vaddr_out == load_vaddr);

    @(negedge clk);

    loadValid = 1'b1;
    load_vaddr = 48'h1FFFFFFFF000;
    load_id = 4'd3;
    tlb_paddr_in = 30'h3291322e;
    addrStart2 = tlb_paddr_in;
    tlb_paddr_ready = 1'b1;
    l2_ready_for_req = 1'b1;
    $display("\nWork stage3 and 2 and take another load, provide tlb");
    $display("Wanted paddr l2: %x\n", addrStart1[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    print_cache();
    assert(tlb_vaddr_valid);
    assert(tlb_vaddr_out == load_vaddr);
    assert(l2_req_valid);
    assert(!l2_req_rw);
    assert(l2_req_paddr == addrStart1[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    assert(l2_query_id == load_id);
    assert(!l2_evict_valid);

    @(negedge clk);
    loadValid = 1'b1;
    load_vaddr = 48'h1FA000000000;
    load_id = 4'd4;
    tlb_paddr_in = 30'h25EAB212;
    tlb_paddr_ready = 1'b0;
    l2_ready_for_req = 1'b1;
    $display("\nWork stage3 and 2 and take another load, dont provide tlb, blocking stage 2");
    $display("Wanted paddr l2: %x\n", addrStart1[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    print_cache();

    // assert(tlb_vaddr_valid);
    // assert(tlb_vaddr_out == load_vaddr);
    assert(l2_req_valid);
    assert(!l2_req_rw);
    assert(l2_req_paddr == addrStart2[PADDR_W-1:$clog2(BLOCK_SIZE)]);
    assert(l2_query_id == load_id);
    assert(!l2_evict_valid);

    $display("Test III passed");
    reset_test_state();
endtask

initial begin
    test1();
    test2();
    test3();

    $finish();
end

endmodule

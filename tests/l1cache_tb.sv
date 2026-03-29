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
logic l2_ready_for_resp;

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
    .l2_ready_for_req(l2_ready_for_resp),
    .l2_resp_valid(l2_resp_valid),
    .l2_resp_data(l2_resp_data),
    .l2_resp_id(l2_resp_id),
    .l2_paddr(l2_paddr),
    .tlb_paddr_in(tlb_paddr_in),
    .tlb_paddr_ready(tlb_paddr_ready),
    .tlb_vaddr_out(tlb_vaddr_out),
    .tlb_vaddr_valid(tlb_vaddr_valid)
);

  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
    end
  end

logic DBG;

  task print_cache;
    #1; 

    if (DBG) begin
        $display("<----------------------------------- CACHE PINS IN ---------------------------------->");
        $display("| %-4s | %-4s | %-5s | %-5s | %-14s | %-14s | %-18s |", "ST_V", "LD_V", "ST_ID", "LD_ID", "ST_ADDR", "LD_ADDR", "ST_DATA");
        $display("| %-4b | %-4b | %-5d | %-5d | 0x%-12x | 0x%-12x | 0x%-16x |", storeValid, loadValid, store_id, load_id, store_vaddr, load_vaddr, store_data);

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
    l2_ready_for_resp = 0;
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
  $display("Say l2 accepts");
  l2_ready_for_resp = 1'b1;

    #1
    assert(l2_req_valid);
    assert(l2_req_paddr == tlb_paddr_in[29:6]);
    
  $display("Test I passed");
  reset_test_state();
endtask

task test2();

    $display("\n\n\n\nTest II: Test whole cache pipeline");
    // go all the way thru with a load
    print_cache();
    assert(l1ready);

    loadValid = 1'b1;
    load_vaddr = 48'hfef3fff323e;
    load_id = 4'd3;
    
    @(negedge clk);
    assert(tlb_vaddr_valid);
    assert(tlb_vaddr_out == load_vaddr);
    assert(load_received);

    loadValid = 0;
    @(negedge clk);

    tlb_paddr_in = 30'h329034fe;
    tlb_paddr_ready = 1;

    @(negedge clk);

    tlb_paddr_ready = 0;
    l2_ready_for_resp = 1;

    @(negedge clk);

    print_cache();

    assert(l2_req_valid);
    assert(!l2_req_rw);
    assert(l2_req_paddr == tlb_paddr_in[29:6]);
    assert(l2_query_id == 4'd3);
    assert(!l2_evict_valid);
    
    $display("Test II passed");
    reset_test_state();
endtask

task test3();
    
    $display("Test III passed");
    reset_test_state();
endtask

initial begin

    if (!$value$plusargs("DEBUG=%b", DBG)) begin
        DBG = 0;
    end

    test1();
    test2();
    test3();

    $finish();
end

endmodule

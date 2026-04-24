`timescale 1ns / 1ps

module test();

logic clk;
logic reset;

logic fetch_valid;
logic [63:0] fetch_vaddr;
logic fetch_hit;
logic [29:0] fetch_paddr;
logic fetch_miss;
logic fetch_ready;

logic mem_ready;
logic mem_valid_i;
logic [511:0] mem_rdata;
logic [29:0] mem_addr;
logic mem_valid_o;

itlb #() i (
    .clk(clk),
    .reset(reset),
    .ttbr0(0),
    .fetch_valid_i(fetch_valid),
    .fetch_vaddr_i(fetch_vaddr),
    .fetch_hit_o(fetch_hit),
    .fetch_paddr_o(fetch_paddr),
    .fetch_miss_o(fetch_miss),
    .fetch_ready_o(fetch_ready),
    .mem_ready_i(mem_ready),
    .mem_valid_i(mem_valid_i),
    .mem_rdata_i(mem_rdata),
    .mem_addr_o(mem_addr),
    .mem_valid_o(mem_valid_o)
);

initial begin
    clk = 0;
    forever begin
        #5 clk = ~clk;
    end
end

task reset_st;
    reset = 1;
    fetch_vaddr = 0;
    mem_ready = 1;
    mem_valid_i = 0;
    mem_rdata = 0;

    @(negedge clk);
    reset = 0;

endtask

task test_reg;
    fetch_vaddr = 10;
    @(negedge clk);
    assert(fetch_ready);
    assert(fetch_miss);
    fetch_valid = 1;
    @(negedge clk);
    fetch_valid = 0;
    assert(~fetch_ready);
    mem_ready = 1;
    @(negedge clk);
    assert(~mem_valid_o);
    mem_ready = 0;
    mem_valid_i = 1;
    mem_rdata = 512'hffffffffffff;
    assert(~fetch_hit);
    @(negedge clk);
    assert(fetch_hit);
    assert(~fetch_miss);
    assert(fetch_ready);
    $display("hit w %x", fetch_paddr);

    reset_st();
endtask

task test_req_waiting;
    $display("Beginning test2");
    fetch_vaddr = 10; 
    @(negedge clk);
    assert(fetch_ready);
    assert(fetch_miss);
    fetch_valid = 1;
    @(negedge clk);
    assert(~fetch_ready);
    fetch_vaddr = 11;
    mem_ready = 1;
    @(negedge clk);
    assert(~mem_valid_o);
    mem_ready = 0;
    mem_valid_i = 1;
    mem_rdata = 512'hffffffffffff;
    assert(~fetch_hit);
    @(negedge clk);
    assert(fetch_hit);
    assert(~fetch_miss);
    assert(fetch_ready);
    assert(fetch_paddr[3:0] == 'ha);
    @(negedge clk);
    assert(fetch_hit);
    assert(fetch_ready);
    assert(fetch_paddr[3:0] == 'hb);

    reset_st();


endtask

initial begin
    reset_st();
    test_reg();
    test_req_waiting();

    $finish();
end

endmodule



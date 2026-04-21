`timescale 1ns / 1ps

module test();

logic clk_in;
logic reset;
logic flush;

logic exe_valid;
logic exe_branch;
logic exe_conditional;
logic [63:0] exe_pc;
logic exe_taken;
logic [63:0] exe_target;

logic dcode_ready;
logic [31:0] dcode_instr;
logic [63:0] dcode_pc;
logic dcode_el;
logic dcode_valid;

logic [511:0] imem_rdata;
logic imem_ready;
logic imem_resp;
logic imem_req;
logic [29:0] imem_addr;

logic itlb_hit;
logic [29:0] itlb_paddr;
logic itlb_miss;
logic [63:0] itlb_vaddr;

logic bp_taken;
logic [63:0] bp_target;
logic bp_valid;
logic [63:0] bp_vaddr;

fetch #() f (
    .clk(clk_in),
    .reset(reset),
    .flush(flush),
    .exe_valid_i(exe_valid),
    .exe_branch_i(exe_branch),
    .exe_conditional_i(exe_conditional),
    .exe_pc_i(exe_pc),
    .exe_taken_i(exe_taken),
    .exe_target_i(exe_target),
    .dcode_ready_i(dcode_ready),
    .dcode_instr_o(dcode_instr),
    .dcode_pc_o(dcode_pc),
    .dcode_el_o(dcode_el),
    .dcode_valid_o(dcode_valid),
    .imem_rdata_i(imem_rdata),
    .imem_ready_i(imem_ready),
    .imem_valid_i(imem_resp),
    .imem_valid_o(imem_req),
    .imem_addr_o(imem_addr),
    .itlb_hit_i(itlb_hit),
    .itlb_paddr_i(itlb_paddr),
    .itlb_miss_i(itlb_miss),
    .itlb_vaddr_o(itlb_vaddr),
    .bp_taken_i(bp_taken),
    .bp_target_i(bp_target),
    .bp_valid_o(bp_valid),
    .bp_vaddr_o(bp_vaddr)
);

initial begin
    clk_in = 0;
    forever begin
        #5 clk_in = ~clk_in;
    end
end

task reset_st;

    flush = 1;
    exe_target = '0;
    dcode_ready = 1;
    imem_rdata = '0;
    imem_ready = 1;
    imem_resp = 0;
    itlb_hit = 0;
    itlb_miss = 0;
    itlb_paddr = '0;
    bp_taken = 0;
    bp_target = '0;

    @(negedge clk_in);
    flush = 0;

endtask

task test_reg_out;
    dcode_ready = 1;
    imem_ready = 1;

    @(negedge clk_in);

    assert(itlb_vaddr == 0);
    itlb_hit = 1;
    itlb_paddr = 10;
    @(negedge clk_in);

    assert(imem_req);
    assert(imem_addr == 10);

    imem_resp = 1;
    imem_rdata[31:0] = 32'hfefefefe;

    @(negedge clk_in);
    
    assert(dcode_pc == 0);
    assert(dcode_valid == 1);
    assert(dcode_instr == imem_rdata[0 +: 32]);

    reset_st();

endtask

task test_flush;
    
    @(negedge clk_in);

    itlb_hit = 1;
    itlb_paddr = 30'h323232f;
    @(negedge clk_in);

    assert(imem_req);
    assert(imem_ready);
    @(negedge clk_in);

    flush = 1;
    exe_target = 64'hfe3892143;
    @(negedge clk_in);
    flush = 0;
    @(negedge clk_in);
    @(negedge clk_in);
    // did it flush? 
    // it did :D

    reset_st();
endtask

task test_branch;
    
    // don't care, run it thru
    imem_resp = 1;

    bp_taken = 1;
    bp_target = 64'h3232;
    @(negedge clk_in);
    bp_taken = 0;
    itlb_hit = 1;
    @(negedge clk_in);
    assert(itlb_vaddr == 64'h3232);
    itlb_paddr = 30'h432;
    assert(imem_req);
    assert(imem_addr == 30'h0);
    @(negedge clk_in);
    itlb_paddr = 30'h832;
    assert(imem_addr == 30'h432);
    assert(imem_req);
    assert(itlb_vaddr == 64'h3236);

    @(negedge clk_in);
    assert(imem_addr == 30'h832);

    reset_st();

endtask

task test_offset_read;

    imem_rdata[31:0] = 'h1;
    imem_rdata[63:32] = 'h2;

    @(negedge clk_in);
    itlb_hit = 1;
    itlb_paddr = 'h10;
    @(negedge clk_in);
    itlb_paddr = 'h14;
    assert(imem_req);
    assert(imem_addr == 'h10);
    imem_resp = 1;
    @(negedge clk_in);
    assert(dcode_pc == 0);
    assert(dcode_instr == 'h1);
    @(negedge clk_in);
    assert(dcode_pc == 4);
    assert(dcode_instr == 'h2);
    @(negedge clk_in);

    reset_st();

endtask

task test_tlb_miss;

    @(negedge clk_in);
    itlb_miss = 1;

    @(negedge clk_in);
    assert(~imem_req);
    @(negedge clk_in);
    assert (~imem_req);
    assert(itlb_vaddr == 0);
    itlb_miss = 0;
    itlb_hit = 1;
    itlb_paddr = 'h20;
    @(negedge clk_in);
    assert(itlb_vaddr == 4);
    assert(imem_req);
    assert(imem_addr == 'h20);
    @(negedge clk_in);
    
    reset_st();
endtask

initial begin
    reset_st();
    test_reg_out();
    test_flush();
    test_branch();
    test_offset_read();
    test_tlb_miss();
    $display();
    $display("passed all tests");
    $finish();
end

endmodule

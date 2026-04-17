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

initial begin
    
    $display("hello there\n");
end

endmodule

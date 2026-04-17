`timescale 1ns / 1ps

module fetch (
    
    // default inputs + flush
    input logic clk,
    input logic reset,
    input logic flush, // not sure we need this, could just use execute

    // execute
    input logic         exe_valid_i,
    input logic         exe_branch_i,
    input logic         exe_conditional_i,
    input logic [63:0]  exe_pc_i,
    input logic         exe_taken_i,
    input logic [63:0]  exe_target_i,

    // decode
    input logic         dcode_ready_i,
    output logic [31:0] dcode_instr_o,
    output logic [63:0] dcode_pc_o,
    output logic        dcode_el_o, // what is this, what does it do?
    output logic        dcode_valid_o,
    
    // backend
    input logic [511:0] imem_rdata_i,
    input logic         imem_ready_i,
    output logic        imem_valid_o,
    output logic [29:0] imem_addr_o,

    // iTLB
    input logic         itlb_hit_i,
    input logic [29:0]  itlb_paddr_i,
    input logic         itlb_miss_i, // not sure this is necessary
    output logic        itlb_vaddr_o, 
    // output logic       itlb_valid_o,

    // branch predictor
    input logic         bp_taken_i,
    input logic [63:0]  bp_target_i,
    output logic        bp_valid_o,
    output logic [63:0] bp_vaddr_o

);

    logic [63:0] pc;  

    typedef struct { 
        logic        valid,
        logic        stall,
        logic [63:0] vaddr,
        logic [29:0] paddr,
        logic [31:0] instr // only used in stage3
    } stage_t;

    // stage 1: query iTLB, query branch predictor
    // stage 2: fetch from memory, set next pc
    // stage 3: set decode values
    stage_t stage1, stage2, stage3;
    
    assign stage2.stall = stage3.stall;
    assign stage1.stall = stage2.stall;

    assign dcode_valid_o = stage3.valid & ~stage3.stall;
    assign dcode_pc_o    = stage3.vaddr;
    assign dcode_instr_o = stage3.instr;

    intial begin
        $display("hello there\n");
        pc = '0;

        // do i need to start fetching here? or can i assume that pc should go pc + 4 imm
    end

    always_ff @(posedge clk) begin


    end

	// TODO: fetch 


endmodule

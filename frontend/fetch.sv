`timescale 1ns / 1ps

module fetch (
    
    // default inputs + flush
    input logic clk,
    input logic reset,
    input logic flush, // not sure we need this, could just use execute

    // execute/commit
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
    input logic         imem_valid_i, // their response is valid
    output logic        imem_valid_o, // our request is valid
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
        logic        compl,
        logic        stall,
        logic [63:0] vaddr,
        logic [29:0] paddr,
        logic [31:0] instr // only used in stage3
    } stage_t;

    // stage 1: query iTLB, query branch predictor
    // stage 2: fetch from memory, set next pc
    // stage 3: set decode values
    stage_t stage1, stage2, stage3;

    task print_stages;
        if (DBG) begin
            $display("\n| %-16s | %-16s | %-16s |\n", "Stage I", "Stage II", "Stage III");
            $display("| %d%15s | %d%15s | %d%15s |\n", stage1.valid, "", stage2.valid, "", stage3.valid, "");
            $display("| %d%15s | %d%15s | %d%15s |\n", stage1.stall, "", stage2.stall, "", stage3.stall, "");
            $display("| %016x | %016x | %016x |\n", stage1.vaddr, stage2.vaddr, stage3.vaddr);
            $display("| %08x%8s | %08x%8s | %08x%8s |\n", stage1.paddr, "", stage2.paddr, "", stage3.paddr, "");
            $display("| %08x%8s | %08x%8s | %08x%8s |\n\n", stage1.instr, "", stage2.instr, "", stage3.instr, "");
        end

    endtask
    
    // stage 3 stalls if memory isn't valid
    assign stage3.stall = ~imem_valid_i;

    // stage 2 stalls if stage 3 is stalled or if memory is not ready
    // to take a request or if tlb hasn't given us a paddr yet
    // TODO: how does tlb behave on a miss, will this work?
    assign stage2.stall = stage3.stall | ~imem_ready_i | ~itlb_miss_i;

    assign stage1.stall = stage2.stall;


    assign bp_valid_o = stage1.valid;
    assign bp_vaddr_o = pc;
    
    assign dcode_valid_o = stage3.compl;
    assign dcode_pc_o    = stage3.vaddr;
    assign dcode_instr_o = stage3.instr;

    logic DBG;
    initial begin
        // set DBG to 0 if argument is not given
        if (!$value$plusargs("FDEBUG=%b", DBG)) begin
            DBG = 0;
        end

        pc = '0;

        print_stages();
    end

    always_ff @(posedge clk) begin
        
        // stage 3 stuff
        // by now, its a safe assumption that we queried memory for our address,
        // so we should just set decode values, assuming memory came back
        if (stage3.valid) begin
            
            // this could be optimized to be so much better, and maybe i will
            // down the line. for now, it's unnecessary and we will do the
            // trivial version.
            if (imem_valid_i) begin
                stage3.instr <= imem_rdata_i[31:0];
                stage3.compl <= 1;
            end

        end

        if (stage2.valid && ~stage2.stall) begin
            
            if (imem_ready_i) begin

            end // if this is false, should stall through assign statement
        end

        if (stage1.valid && ~stage1.stall) begin
            // bp query is done combinatorially, we should just be able to read the output
            itlb_vaddr_o <= pc;

            if (bp_taken_i) begin
                pc <= bp_target_i; 
            end else begin
             pc <= pc + 64'd4;

             // move stage 1 information to stage2

        end

    end

endmodule

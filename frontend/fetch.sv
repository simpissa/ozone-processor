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
    output logic [63:0] itlb_vaddr_o, 
    // output logic       itlb_valid_o,

    // branch predictor
    input logic         bp_taken_i,
    input logic [63:0]  bp_target_i,
    output logic        bp_valid_o,
    output logic [63:0] bp_vaddr_o

);

    logic [63:0] pc;


    typedef struct packed { 
        logic        valid;
        logic        compl;
        logic [63:0] vaddr;
        logic [29:0] paddr;
        logic [31:0] instr;
    } stageiii_t;

    typedef struct packed {
        logic valid;
        logic [63:0] vaddr;
        logic [29:0] paddr;
    } stageii_t;

    typedef struct packed {
        logic valid;
        logic [63:0] vaddr;
    } stagei_t;



    // stage 1: query iTLB, query branch predictor
    // stage 2: fetch from memory, set next pc
    // stage 3: set decode values
    stagei_t stage1;
    stageii_t stage2;
    stageiii_t stage3;


    logic stage1_stall, stage2_stall, stage3_stall;

    task print_stages;
        if (DBG) begin
            $display("\nStage -> | %-16s | %-16s | %-16s |", "Stage I", "Stage II", "Stage III");
            $display("Valid -> | %d%15s | %d%15s | %d%15s |", stage1.valid, "", stage2.valid, "", stage3.valid, "");
            $display("Stall -> | %d%15s | %d%15s | %d%15s |", stage1_stall, "", stage2_stall, "", stage3_stall, "");
            $display("Vaddr -> | %016x | %016x | %016x |", stage1.vaddr, stage2.vaddr, stage3.vaddr);
            $display("Paddr -> | %16s | %08x%8s | %08x%8s |", "N/A", stage2.paddr, "", stage3.paddr, "");
            $display("Instr -> | %16s | %16s | %08x%8s |\n", "N/A", "N/A", stage3.instr, "");
        end

    endtask

    task move_stages;
        
        if (~stage3_stall) begin
            // move stage 3 out
            stage3.valid <= 0;
            stage3.compl <= 0;
            stage3.vaddr <= '0;
            stage3.paddr <= '0;
            stage3.instr <= '0;
        end
        
        // move stage 2 -> stage 3, move stage 2 out
        if (~stage2_stall) begin
            stage3.valid <= stage2.valid;
            stage3.vaddr <= stage2.vaddr;
            stage3.paddr <= stage2.paddr;

            stage2.valid <= 0;
            stage2.vaddr <= '0;
            stage2.paddr <= '0;
        end
        
        // move stage 1 -> stage 2, move stage 1 out
        if (~stage1_stall) begin
            stage2.valid <= stage1.valid;
            stage2.vaddr <= stage1.vaddr;
            
        end


    endtask
    
    // stage 3 stalls if memory isn't valid
    assign stage3_stall = ~imem_valid_i;

    // stage 2 stalls if stage 3 is stalled or if memory is not ready
    // to take a request or if tlb hasn't given us a paddr yet
    // TODO: how does tlb behave on a miss, will this work?
    assign stage2_stall = stage3_stall | ~imem_ready_i | ~itlb_miss_i;

    assign stage1_stall = stage2_stall;

    assign stage1.valid = 1;
    assign stage1.vaddr = pc;

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
        if (stage3.valid && ~stage3_stall) begin
            
            // this could be optimized to be so much better, and maybe i will
            // down the line. for now, it's unnecessary and we will do the
            // trivial version.
            if (imem_valid_i) begin
                stage3.instr <= imem_rdata_i[31:0];
                stage3.compl <= 1;
            end

        end


        imem_valid_o <= 0;
        if (stage2.valid && ~stage2_stall) begin

            if (itlb_hit_i) begin
                stage2.paddr <= itlb_paddr_i;
            end
             
            if (imem_ready_i) begin
                imem_addr_o <= itlb_paddr_i;
                imem_valid_o <= 1;
            end // if this is false, should stall through assign statement
        end

        if (stage1.valid && ~stage1_stall) begin
            // bp query is done combinatorially, we should just be able to read the output
            itlb_vaddr_o <= pc;

            if (bp_taken_i) begin
                pc <= bp_target_i; 
            end else begin
                pc <= pc + 64'd4;
            end

        end

        move_stages();

    end

endmodule

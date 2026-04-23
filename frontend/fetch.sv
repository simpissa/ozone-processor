`timescale 1ns / 1ps

module fetch (
    
    // default inputs + flush
    input logic clk,
    input logic reset,
    input logic flush, // not sure we need this, could just use execute
    
    // or is it this we don't need?
    // should be pretty easy to just get the flush signal and say goodbye
    // if that's the case, we still need to know where our pc should be, so
    // we need to keep one input for that
    // execute/commit 
    /*
    input logic         exe_valid_i,
    input logic         exe_branch_i,
    input logic         exe_conditional_i,
    input logic [63:0]  exe_pc_i,
    input logic         exe_taken_i,
    */
    input logic [63:0]  exe_target_i,

    // decode
    input logic         dcode_ready_i,
    output logic [31:0] dcode_instr_o,
    output logic [63:0] dcode_pc_o,
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
    input logic         itlb_miss_i,
    output logic [63:0] itlb_vaddr_o, 
    // output logic       itlb_valid_o,

    // branch predictor
    input logic         bp_taken_i,
    input logic [63:0]  bp_target_i,
    output logic        bp_valid_o,
    output logic [63:0] bp_vaddr_o

);

    logic [63:0] pc;
    logic [30:0] paddr_offset; // used to determine if we need to ask mem for another read or we can just query;

    // Note: This stage information is mostly used for debugging. it does little
    // in way of actually moving information between stages
    typedef struct packed { 
        logic        valid;
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
    stageiii_t stage4;
    logic stage1_stall, stage2_stall, stage3_stall, stage4_stall;

    task print_stages;
        if (DBG) begin
            $display("\nStage -> | %-16s | %-16s | %-16s | %-16s |", "Stage I", "Stage II", "Stage III", "Stage IV");
            $display("Valid -> | %d%15s | %d%15s | %d%15s | %d%15s |", stage1.valid, "", stage2.valid, "", stage3.valid, "", stage4.valid, "");
            $display("Stall -> | %d%15s | %d%15s | %d%15s | %d%15s |", stage1_stall, "", stage2_stall, "", stage3_stall, "", stage4_stall, "");
            $display("Vaddr -> | %016x | %016x | %016x | %016x |", stage1.vaddr, stage2.vaddr, stage3.vaddr, stage4.vaddr);
            $display("Paddr -> | %16s | %08x%8s | %08x%8s | %08x%8s |", "N/A", stage2.paddr, "", stage3.paddr, "", stage4.paddr, "");
            $display("Instr -> | %16s | %16s | %08x%8s | %08x%8s |\n", "N/A", "N/A", stage3.instr, "", stage4.instr, "");
        end

    endtask

    task move_stages;

        if (~stage4_stall) begin
            stage4.valid <= 0;
            stage4.vaddr <= '0;
            stage4.paddr <= '0;
            stage4.instr <= '0;
        end
        
        if (~stage3_stall) begin
            stage4.valid <= stage3.valid;
            stage4.vaddr <= stage3.vaddr;
            stage4.paddr <= stage3.paddr;
            assert(paddr_offset[8:0] <= 480);
            stage4.instr <= imem_rdata_i[paddr_offset[8:0] +: 32];

            // move stage 3 out
            stage3.valid <= 0;
            stage3.vaddr <= '0;
            stage3.paddr <= '0;
            stage3.instr <= '0;
        end
        
        // move stage 2 -> stage 3, move stage 2 out
        if (~stage2_stall) begin
            stage3.valid <= stage2.valid;
            stage3.vaddr <= stage2.vaddr;
            stage3.paddr <= itlb_paddr_i;

            stage2.valid <= 0;
            stage2.vaddr <= '0;
            stage2.paddr <= '0;
        end
        
        // move stage 1 -> stage 2, move stage 1 out
        if (~stage1_stall) begin
            stage2.valid <= stage1.valid;
            stage2.vaddr <= stage1.vaddr;
        end

        if (flush) begin
            stage4.valid <= 0;
            stage4.vaddr <= '0;
            stage4.paddr <= '0;
            stage4.instr <= '0;

            stage3.valid <= 0;
            stage3.vaddr <= '0;
            stage3.paddr <= '0;
            stage3.instr <= '0;

            stage2.valid <= 0;
            stage2.vaddr <= '0;
            stage2.paddr <= '0;
            
            if (DBG)
                $display("Flushed... setting pc to %x", exe_target_i);
            
            // stage1 is always set valid
            pc <= exe_target_i;
        end

    endtask

    assign paddr_offset = (stage3.paddr - imem_addr_o) * 8;

    assign stage4_stall = ~dcode_ready_i;

    // stage 3 stalls if memory isn't valid
    assign stage3_stall = (stage4_stall && stage4.valid) | ~imem_valid_i;

    // stage 2 stalls if stage 3 is stalled or if memory is not ready
    // to take a request or if tlb hasn't given us a paddr yet
    // TODO: how does tlb behave on a miss, will this work?
    assign stage2_stall = (stage3_stall && stage3.valid) | ~imem_ready_i | itlb_miss_i;

    assign stage1_stall = (stage2_stall && stage2.valid);

    assign stage1.valid = 1;
    assign stage1.vaddr = pc;

    assign bp_valid_o = stage1.valid;
    assign bp_vaddr_o = pc;
    
    assign dcode_valid_o = stage4.valid;
    assign dcode_pc_o    = stage4.vaddr;
    assign dcode_instr_o = stage4.instr;

    logic DBG;
    initial begin
        // set DBG to 0 if argument is not given
        if (!$value$plusargs("FDEBUG=%b", DBG)) begin
            DBG = 0;
        end

        pc = '0;
    end

    always_ff @(posedge clk) begin

        print_stages();
        
        // stage 3 stuff
        // by now, its a safe assumption that we queried memory for our address,
        // so we should just set decode values, assuming memory came back
        if (stage3.valid && ~stage3_stall) begin

            // this could be optimized to be so much better, and maybe i will
            // down the line. for now, it's unnecessary and we will do the
            // trivial version.
            if (imem_valid_i) begin
                if (DBG)
                    $display("Fetch State: Receiving data from memory");
                //$display("offs %d, mem_addr %d, our addr %d itlb %d", paddr_offset, imem_addr_o, stage3.paddr, itlb_paddr_i);

                assert(!(|paddr_offset[30:9]));
                stage3.instr <= imem_rdata_i[paddr_offset[8:0] +: 32];
            end

        end
        
        if (imem_valid_o && imem_ready_i)
            imem_valid_o <= 0;

        if (stage2.valid && ~stage2_stall) begin
            assert(itlb_hit_i);

            if (itlb_hit_i) begin
                if (DBG)
                    $display("Fetch State: Receiving paddr %x from iTLB", itlb_paddr_i);

                stage2.paddr <= itlb_paddr_i;

                // do we actually need to query?
                if (!(imem_valid_i && (itlb_paddr_i > imem_addr_o) && ((itlb_paddr_i - imem_addr_o) * 8 <= 480))) begin
                    imem_addr_o <= itlb_paddr_i;
                    imem_valid_o <= 1;

                end

            end
             
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

`timescale 1ns / 1ps

typedef enum logic [2:0] {
    FU_ALU,
    FU_SHIFTER,
    FU_LOGIC,
    FU_AGU,
    FU_FPU,
    FU_MEM
} fu_t; // functional units

typedef enum logic [4:0] {
    OP_ADD,
    OP_SUB, // TODO: add more
} fu_op_t; // which op to execute, depends on our fus

typedef enum logic [5:0] {
    I_LDUR, I_STUR, I_MOVK, I_MOVZ, I_ADRP, 
    // TODO: add rest of instructions
    I_B, I_BCOND, I_BL, I_RET,
    I_NOP, I_ERET, I_MRS, I_MSR, I_SVC,
} instr_id_t;

module decoder (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions (if in the middle of outputting multiple uops)

    // fetch i/o
    input  logic [31:0] instr,
    input  logic [63:0] pc, // needed for branch instructions
    input  logic        el,
    input  logic        valid_in,
    output logic        ready_out,

    // next stage (rob or rat?) i/o
    output logic        valid_out,
    input logic         ready_in,

    // Micro-op descriptor, one per cycle
    output fu_t         fu_select, 
    output fu_op_t      fu_op,
    output logic [4:0]  rd, // destination register
    output logic        r_dest_valid,
    output logic [4:0]  rs1, // source register 1
    output logic        rs1_valid,
    output logic [4:0]  rs2, // source register 2
    output logic        rs2_valid,
    output logic [63:0] imm, // immediate 
    output logic        imm_valid,

    // Multi-uop control
    output logic        first_uop, // allocate rob entry on this
    output logic        last_uop, 
    output logic        is_sequential, // data dependence between uops

    // Extra data
    output logic [3:0]  cond,
    output logic [63:0] branch_target,
    output logic [3:0]  spr_id // special purpose register id
    // TODO: add more if uop needs it
);

    logic [1:0] uop_counter;

    // which uop to output for the current instruction, since decoding is combinational
    always_ff @(posedge clk) begin
        if (rst || flush)
            uop_counter <= 0;
        else if (valid_out && ready_in) begin
            if (last_uop)
                uop_counter <= 0;
            else
                uop_counter <= uop_counter + 1;
        end
    end
    
    instr_id_t instr_id;

    // Identify opcode
    always_comb begin
        instr_id = 
    end
    
    // set outputs
    always_comb begin
        case instr_id:

            // =============================================================
            // DATA TRANSFER
            // =============================================================


            // =============================================================
            // DATA PROCESSING: IMMEDIATE
            // =============================================================

            // =============================================================
            // COMPUTATION (ARITHMETIC, LOGICAL, SHIFT)
            // =============================================================

            // =============================================================
            // CONTROL TRANSFER
            // =============================================================
            I_B: begin
            
            end

            I_BCOND: begin
                case (uop_counter)
                    0: begin // COND_CHECK
                    end

                    1: begin // ADD
                    end
                endcase
            end
            // =============================================================
            // MISC
            // =============================================================

            // =============================================================
            // FLOATING-POINT
            // =============================================================
            
        endcase
    end

endmodule

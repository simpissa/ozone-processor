`timescale 1ns / 1ps

typedef enum logic [2:0] {
    FU_ALU,
    FU_SHIFTER,
    FU_LOGIC,
    FU_AGU,
    FU_FPU,
    FU_MEM,
    FU_NONE
} fu_t; // functional units

typedef enum logic [4:0] {
    OP_ADD,
    OP_SUB,
    OP_COND_CHECK,
    OP_NOP
} fu_op_t; // which op to execute, depends on our fus

typedef enum logic [5:0] {
    I_LDUR, I_STUR, I_MOVK, I_MOVZ, I_ADRP, 
    // TODO: add rest of instructions
    I_B, I_BCOND, I_BL, I_RET,
    I_NOP, I_ERET, I_MRS, I_MSR, I_SVC,
    I_UNKNOWN
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
    output logic        src1_is_pc, // use pc as source register (for branching ops)

    // Multi-uop control
    output logic        first_uop, // allocate rob entry on this
    output logic        last_uop, 
    output logic        is_sequential, // does the current uop depend on a previous uop

    // Extra data
    output logic        is_branch,
    output logic [3:0]  cond,
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

    // fields
    logic [4:0] Rn_field;

    logic [25:0] simm26; // b1
    logic [18:0] simm19; // i2, b2

    logic [3:0]  cond_field; // b2

    logic [63:0] bcond_offset;
    logic [63:0] b_offset;

    assign Rn_field   = instr[9:5];
    assign simm26     = instr[25:0];
    assign simm19     = instr[23:5];
    
    assign cond_field = instr[3:0];
    // from ARM manual: bits(64) offset = SignExtend(imm19:'00', 64);
    assign bcond_offset = {{43{simm19[18]}}, simm19, 2'b00};
    assign b_offset     = {{36{simm26[25]}}, simm26, 2'b00};

    // Identify opcode
    always_comb begin
        instr_id = I_UNKNOWN;

        unique casez (instr)
        
            // Control transfer
            32'b000101??????????????????????????: instr_id = I_B;
            32'b01010100???????????????????0????: instr_id = I_BCOND;
            32'b100101??????????????????????????: instr_id = I_BL;
            32'b1101011001011111000000?????00000: instr_id = I_RET;

            default: instr_id = I_UNKNOWN;
        endcase
    end
    
    // set outputs
    always_comb begin
        // set defaults
        valid_out      = valid_in;
        fu_select      = FU_NONE;
        fu_op          = OP_NOP;
        rd             = 5'd31;
        r_dest_valid   = 1'b0;
        rs1            = 5'd31;
        rs1_valid      = 1'b0;
        rs2            = 5'd31;
        rs2_valid      = 1'b0;
        imm            = 64'd0;
        imm_valid      = 1'b0;
        src1_is_pc     = 1'b0;
        first_uop      = (uop_counter == 0);
        last_uop       = 1'b1; // default to 1, set to 0 if not
        is_sequential  = 1'b0;
        is_branch      = 1'b0;
        cond           = 4'd0;
        spr_id         = 4'd0;


        case (instr_id)
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
                is_branch     = 1'b1;
                fu_select     = FU_ALU;
                fu_op         = OP_ADD;
                imm           = b_offset;
                imm_valid     = 1'b1;
                src1_is_pc    = 1'b1;
            end

            I_BCOND: begin
                is_branch     = 1'b1;
                cond          = cond_field;

                case (uop_counter)
                    0: begin // COND_CHECK
                        fu_select = ; // TODO: which fu does COND_CHECK go to?
                        fu_op     = OP_COND_CHECK;
                        last_uop  = 1'b0;
                    end

                    1: begin // ADD
                        fu_select     = FU_ALU;
                        fu_op         = OP_ADD;
                        imm           = bcond_offset;
                        imm_valid     = 1'b1;
                        src1_is_pc    = 1'b1;
                        is_sequential = 1'b0;
                    end
                endcase
            end

            I_BL: begin
                // ARM page 60: Branch with Link branches to a PC-relative offset, setting the register X30 to PC+4
                is_branch     = 1'b1;
                case (uop_counter)
                    0: begin
                        fu_select    = FU_ALU;
                        fu_op        = OP_ADD;
                        imm          = 64'd4;
                        imm_valid    = 1'b1;
                        src1_is_pc   = 1'b1;
                        rd           = 5'd30;
                        r_dest_valid = 1'b1;
                        last_uop     = 1'b0;
                    end

                    1: begin
                        fu_select     = FU_ALU;
                        fu_op         = OP_ADD;
                        imm           = b_offset;
                        imm_valid     = 1'b1;
                        src1_is_pc    = 1'b1;
                        is_sequential = 1'b0;
                    end
                endcase
            end

            I_RET: begin
                is_branch = 1'b1;
                fu_select = FU_LOGIC;
                fu_op     = ; // TODO: which op is OR w/ XZR?
                rs1       = Rn_field;
                rs1_valid = 1'b1;
            end

            // =============================================================
            // MISC
            // =============================================================

            // =============================================================
            // FLOATING-POINT
            // =============================================================

            default: begin
            end
        endcase
    end

endmodule

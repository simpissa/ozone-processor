`timescale 1ns / 1ps

import frontend_types::*;

typedef enum logic [5:0] {
    I_LDUR, I_STUR, I_MOVK, I_MOVZ, I_ADRP,
    I_ADD, I_ADDS, I_SUB, I_SUBS,
    // TODO: add rest of instructions
    I_B, I_BCOND, I_BL, I_RET,
    I_NOP, I_ERET, I_MRS, I_MSR, I_SVC,
    I_F_LDUR, I_F_STUR, I_FMOV, I_FNEG, I_FADD, I_FMUL, I_FSUB, I_FCMP_RR, I_FCMP_RI,
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

    // next stage (rename) i/o
    output logic        valid_out,
    input logic         ready_in,

    // Micro-op descriptor, one per cycle
    output uop_t        uop
);

    // Backpressure fetch: only accept a new instruction when rename can
    // consume the current uop AND this is the last uop of the instruction.
    assign ready_out = ready_in && uop.last_uop;

    logic [1:0] uop_counter;

    // which uop to output for the current instruction, since decoding is combinational
    always_ff @(posedge clk) begin
        if (rst || flush)
            uop_counter <= 0;
        else if (valid_out && ready_in) begin
            if (uop.last_uop)
                uop_counter <= 0;
            else
                uop_counter <= uop_counter + 1;
        end
    end
    
    instr_id_t instr_id;

    // fields
    logic [4:0] Rn_field;
    logic [4:0] RmField;

    logic [25:0] simm26; // b1
    logic [18:0] simm19; // i2, b2
    logic [15:0] imm16;  // i1 / sysreg field

    logic [3:0]  cond_field; // b2
    spr_t        decoded_spr_id;

    logic [63:0] bcond_offset;
    logic [63:0] b_offset;

    assign Rn_field   = instr[9:5];
    assign RmField = instr[20:16];
    assign simm26     = instr[25:0];
    assign simm19     = instr[23:5];
    assign imm16      = instr[20:5];
    
    assign cond_field = instr[3:0];
    // from ARM manual: bits(64) offset = SignExtend(imm19:'00', 64);
    assign bcond_offset = {{43{simm19[18]}}, simm19, 2'b00};
    assign b_offset     = {{36{simm26[25]}}, simm26, 2'b00};


    // special registers
    localparam logic [15:0] SYSREG_SP_EL0    = {2'b11, 3'b000, 4'b0100, 4'b0001, 3'b000};
    localparam logic [15:0] SYSREG_ELR_EL1   = {2'b11, 3'b000, 4'b0100, 4'b0000, 3'b001};
    localparam logic [15:0] SYSREG_SPSR_EL1  = {2'b11, 3'b000, 4'b0100, 4'b0000, 3'b000};
    localparam logic [15:0] SYSREG_VBAR_EL1  = {2'b11, 3'b000, 4'b1100, 4'b0000, 3'b000};
    localparam logic [15:0] SYSREG_ACTLR_EL1 = {2'b11, 3'b000, 4'b0001, 4'b0000, 3'b001};
    always_comb begin
        decoded_spr_id = SPR_INVALID;
        case (imm16)
            SYSREG_SP_EL0:    decoded_spr_id = SPR_SP_EL0;
            SYSREG_ELR_EL1:   decoded_spr_id = SPR_ELR_EL1;
            SYSREG_SPSR_EL1:  decoded_spr_id = SPR_SPSR_EL1;
            SYSREG_VBAR_EL1:  decoded_spr_id = SPR_VBAR_EL1;
            SYSREG_ACTLR_EL1: decoded_spr_id = SPR_ACTLR_EL1;
            default:          decoded_spr_id = SPR_INVALID;
        endcase
    end

    // Identify opcode
    always_comb begin
        instr_id = I_UNKNOWN;

        unique casez (instr)
            // Data transfer
            32'b11111000010?????????00??????????: instr_id = I_LDUR;
            32'b11111000000?????????00??????????: instr_id = I_STUR;

            // Data processing: immediate
            32'b111100101???????????????????????: instr_id = I_MOVK;
            32'b110100101???????????????????????: instr_id = I_MOVZ;
            32'b1??10000????????????????????????: instr_id = I_ADRP;

            // Computation
            32'b1001000100??????????????????????: instr_id = I_ADD;
            32'b10101011??0?????????????????????: instr_id = I_ADDS;
            32'b1101000100??????????????????????: instr_id = I_SUB;
            32'b11101011??0?????????????????????: instr_id = I_SUBS;

            // FP
            32'b11111100010xxxxxxxxx00xxxxxxxxxx : instr_id = I_F_LDUR;
            32'b11111100000xxxxxxxxx00xxxxxxxxxx : instr_id = I_F_STUR;
            32'b0001111001100000010000xxxxxxxxxx : instr_id = I_FMOV;
            32'b0001111001100001010000xxxxxxxxxx : instr_id = I_FNEG;
            32'b00011110011xxxxx001010xxxxxxxxxx : instr_id = I_FADD;
            32'b00011110011xxxxx000010xxxxxxxxxx : instr_id = I_FMUL;
            32'b00011110011xxxxx001110xxxxxxxxxx : instr_id = I_FSUB;
            32'b00011110011xxxxx001000xxxxx00000 : instr_id = I_FCMP_RR;
            32'b00011110011xxxxx001000xxxxx01000 : instr_id = I_FCMP_RI;

            // Control transfer
            32'b000101??????????????????????????: instr_id = I_B;
            32'b01010100???????????????????0????: instr_id = I_BCOND;
            32'b100101??????????????????????????: instr_id = I_BL;
            32'b1101011001011111000000?????00000: instr_id = I_RET;

            // Misc
            32'b11010101000000110010000000011111: instr_id = I_NOP;
            32'b11010110100111110000001111100000: instr_id = I_ERET;
            32'b11010101001?????????????????????: instr_id = I_MRS;
            32'b11010101000?????????????????????: instr_id = I_MSR;
            32'b11010100000????????????????00001: instr_id = I_SVC;

            default: instr_id = I_UNKNOWN;
        endcase
    end
    
    // set outputs
    always_comb begin
        // set defaults
        valid_out          = valid_in;
        uop.fu_select      = FU_NONE;
        uop.fu_op          = OP_NOP;
        uop.rd             = 5'd31;
        uop.r_dest_valid   = 1'b0;
        uop.rs1            = 5'd31;
        uop.rs1_valid      = 1'b0;
        uop.rs2            = 5'd31;
        uop.rs2_valid      = 1'b0;
        uop.imm            = 64'd0;
        uop.imm_valid      = 1'b0;
        uop.src1_is_pc     = 1'b0;
        uop.reads_flags    = 1'b0;
        uop.sets_flags     = 1'b0;
        uop.first_uop      = (uop_counter == 0);
        uop.last_uop       = 1'b1; // default to 1, set to 0 if not
        uop.is_sequential  = 1'b0;
        uop.is_branch      = 1'b0;
        uop.is_store       = 1'b0;
        uop.is_eret        = 1'b0;
        uop.is_msr         = 1'b0;
        uop.is_mrs         = 1'b0;
        uop.is_privileged  = 1'b0;
        uop.is_svc         = 1'b0;
        uop.cond           = 4'd0;
        uop.spr_id         = SPR_INVALID;


        case (instr_id)
            // =============================================================
            // DATA TRANSFER
            // =============================================================

            // Assume that AGU will forward value to memory unit in 1 cycle, once load/store reach
            // the computed address will be available.

            // If rs1=31, is SP not XZR
            I_LDUR: begin
                // AGU + RD
                case (uop_counter)
                    0: begin
                        uop.fu_select=FU_AGU;
                        uop.fu_op=OP_COMPUTE_ADDR;
                        uop.rs1=Rn_field;
                        uop.rs1_valid=1'b1;
                        uop.imm={{55{instr[20]}},instr[20:12]};
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b0;
                    end
                    1: begin
                        uop.fu_select=FU_MEM;
                        uop.fu_op=OP_LOAD;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.last_uop=1'b1;
                    end
                endcase
            end

            I_STUR: begin
                // AGU + WR
                case (uop_counter)
                    0: begin
                        uop.fu_select=FU_AGU;
                        uop.fu_op=OP_COMPUTE_ADDR;
                        uop.rs1=Rn_field;
                        uop.rs1_valid=1'b1;
                        uop.imm={{55{instr[20]}},instr[20:12]};
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b0;
                    end
                    1: begin
                        uop.fu_select=FU_MEM;
                        uop.fu_op=OP_STORE;
                        uop.is_store=1'b1;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.last_uop=1'b1;
                    end
                endcase
            end

            // =============================================================
            // DATA PROCESSING: IMMEDIATE
            // =============================================================
            // If rd=31, is XZR not SP
            I_MOVK: begin
                // AND + OR
                case (uop_counter)
                    0: begin
                        uop.fu_select=FU_LOGIC;
                        uop.fu_op=OP_AND;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=instr[4:0];
                        uop.rs1_valid=1'b1;
                        case (instr[22:21])
                            2'b00: uop.imm={{48{1'b1}},{16{1'b0}}};
                            2'b01: uop.imm={{32{1'b1}},{16{1'b0}},{16{1'b1}}};
                            2'b10: uop.imm={{16{1'b1}},{16{1'b0}},{32{1'b1}}};
                            2'b11: uop.imm={{16{1'b0}},{48{1'b1}}};
                        endcase
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b0;
                    end
                    1: begin
                        uop.fu_select=FU_LOGIC;
                        uop.fu_op=OP_OR;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=instr[4:0];
                        uop.rs1_valid=1'b1;
                        case (instr[22:21])
                            2'b00: uop.imm={{48{1'b0}},instr[20:5]};
                            2'b01: uop.imm={{32{1'b0}},instr[20:5],{16{1'b0}}};
                            2'b10: uop.imm={{16{1'b0}},instr[20:5],{32{1'b0}}};
                            2'b11: uop.imm={instr[20:5],{48{1'b0}}};
                        endcase
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b1;
                    end
                endcase
            end
            I_MOVZ: begin
                // OR w/ XZR
                uop.fu_select=FU_LOGIC;
                uop.fu_op=OP_OR;
                uop.rd=instr[4:0];
                uop.r_dest_valid=1'b1;
                uop.rs1=5'b11111;   // XZR
                uop.rs1_valid=1'b1;
                case (instr[22:21])
                    2'b00: uop.imm={{48{1'b0}},instr[20:5]};
                    2'b01: uop.imm={{32{1'b0}},instr[20:5],{16{1'b0}}};
                    2'b10: uop.imm={{16{1'b0}},instr[20:5],{32{1'b0}}};
                    2'b11: uop.imm={instr[20:5],{48{1'b0}}};
                endcase
                uop.imm_valid=1'b1;
            end
            I_ADRP: begin
                // AND + ADD
                case (uop_counter)
                    0: begin
                        uop.fu_select=FU_LOGIC;
                        uop.fu_op=OP_AND;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.src1_is_pc=1'b1;
                        uop.imm={{52{1'b1}},{12{1'b0}}};
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b0;
                    end
                    1: begin
                        uop.fu_select=FU_ALU;
                        uop.fu_op=OP_ADD;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=instr[4:0];
                        uop.rs1_valid=1'b1;
                        uop.imm={{31{instr[23]}},instr[23:5],instr[30:29],{12{1'b0}}};
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b1;
                    end
                endcase
            end

            // =============================================================
            // COMPUTATION (ARITHMETIC, LOGICAL, SHIFT)
            // =============================================================
            I_ADD: begin
                uop.fu_select=FU_ALU;
                uop.fu_op=OP_ADD;
                uop.rd=instr[4:0];
                uop.r_dest_valid=1'b1;
                uop.rs1=Rn_field;   // In context of ADD (imm), X31 is SP, not XZR
                uop.rs1_valid=1'b1;
                uop.imm={{52{1'b0}},instr[21:10]};
                uop.imm_valid=1'b1;
            end
            I_ADDS: begin
                // In context of ADDS (shifted reg), X31 is XZR, not SP
                // SHIFT + ADD w/ flags
                case (uop_counter)
                    0: begin
                        uop.fu_select=FU_SHIFTER;
                        case (instr[23:22])
                            2'b00: uop.fu_op=OP_LSL;
                            2'b01: uop.fu_op=OP_LSR;
                            2'b10: uop.fu_op=OP_ASR;
                            // 2'b11 reserved (UNDEF)
                        endcase
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=instr[20:16];
                        uop.rs1_valid=1'b1;
                        uop.imm={{58{1'b0}},instr[15:10]};
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b0;
                    end
                    1: begin
                        uop.fu_select=FU_ALU;
                        uop.fu_op=OP_ADD;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=Rn_field;
                        uop.rs1_valid=1'b1;
                        uop.rs2=instr[4:0];
                        uop.rs2_valid=1'b1;
                        uop.sets_flags=1'b1;
                        uop.last_uop=1'b1;
                    end
                endcase
            end
            I_SUB: begin
                uop.fu_select=FU_ALU;
                uop.fu_op=OP_SUB;
                uop.rd=instr[4:0];
                uop.r_dest_valid=1'b1;
                uop.rs1=Rn_field;   // In context of SUB (imm), X31 is SP, not XZR
                uop.rs1_valid=1'b1;
                uop.imm={{52{1'b0}},instr[21:10]};
                uop.imm_valid=1'b1;
            end
            I_SUBS: begin
                // In context of ADDS (shifted reg), X31 is XZR, not SP
                // SHIFT + ADD w/ flags
                case (uop_counter)
                    0: begin
                        uop.fu_select=FU_SHIFTER;
                        case (instr[23:22])
                            2'b00: uop.fu_op=OP_LSL;
                            2'b01: uop.fu_op=OP_LSR;
                            2'b10: uop.fu_op=OP_ASR;
                            // 2'b11 reserved (UNDEF)
                        endcase
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=instr[20:16];
                        uop.rs1_valid=1'b1;
                        uop.imm={{58{1'b0}},instr[15:10]};
                        uop.imm_valid=1'b1;
                        uop.last_uop=1'b0;
                    end
                    1: begin
                        uop.fu_select=FU_ALU;
                        uop.fu_op=OP_SUB;
                        uop.rd=instr[4:0];
                        uop.r_dest_valid=1'b1;
                        uop.rs1=Rn_field;
                        uop.rs1_valid=1'b1;
                        uop.rs2=instr[4:0];
                        uop.rs2_valid=1'b1;
                        uop.sets_flags=1'b1;
                        uop.last_uop=1'b1;
                    end
                endcase
            end

            // =============================================================
            // CONTROL TRANSFER
            // =============================================================
            I_B: begin
                uop.is_branch     = 1'b1;
                uop.fu_select     = FU_ALU;
                uop.fu_op         = OP_ADD;
                uop.imm           = b_offset;
                uop.imm_valid     = 1'b1;
                uop.src1_is_pc    = 1'b1;
            end

            I_BCOND: begin
                uop.is_branch     = 1'b1;
                uop.cond          = cond_field;

                case (uop_counter)
                    0: begin // COND_CHECK
						uop.fu_select   = FU_ALU;
                        uop.fu_op       = OP_COND_CHECK;
                        uop.reads_flags = 1'b1;
                        uop.last_uop    = 1'b0;
                    end

                    1: begin // ADD
                        uop.fu_select     = FU_ALU;
                        uop.fu_op         = OP_ADD;
                        uop.imm           = bcond_offset;
                        uop.imm_valid     = 1'b1;
                        uop.src1_is_pc    = 1'b1;
                    end
                endcase
            end

            I_BL: begin
                // ARM page 60: Branch with Link branches to a PC-relative offset, setting the register X30 to PC+4
                uop.is_branch     = 1'b1;
                case (uop_counter)
                    0: begin
                        uop.fu_select    = FU_ALU;
                        uop.fu_op        = OP_ADD;
                        uop.imm          = 64'd4;
                        uop.imm_valid    = 1'b1;
                        uop.src1_is_pc   = 1'b1;
                        uop.rd           = 5'd30;
                        uop.r_dest_valid = 1'b1;
                        uop.last_uop     = 1'b0;
                    end

                    1: begin
                        uop.fu_select     = FU_ALU;
                        uop.fu_op         = OP_ADD;
                        uop.imm           = b_offset;
                        uop.imm_valid     = 1'b1;
                        uop.src1_is_pc    = 1'b1;
                    end
                endcase
            end

            I_RET: begin
                uop.is_branch = 1'b1;
                uop.fu_select = FU_LOGIC;
                uop.fu_op     = OP_MOV;
                uop.rs1       = Rn_field;
                uop.rs1_valid = 1'b1;
            end

            // =============================================================
            // MISC
            // =============================================================
            I_NOP: begin
                uop.fu_select = FU_NONE;
                uop.fu_op     = OP_NOP;
            end

            I_ERET: begin
                // Arm manual C6.2.87: Exception Return using the ELR and SPSR for the current Exception level. When executed, 
                //             the PE restores PSTATE from the SPSR, and branches to the address held in the ELR.

                // At commit time, switch privilege and restore
                uop.is_eret       = 1'b1;
                uop.is_privileged = 1'b1;

                case (uop_counter)
                    0: begin
                        uop.fu_select = FU_LOGIC;
                        uop.fu_op     = OP_MOV;
                        uop.spr_id    = SPR_ELR_EL1;
                        uop.last_uop  = 1'b0;
                    end

                    1: begin
                        uop.fu_select = FU_LOGIC;
                        uop.fu_op     = OP_MOV;
                        uop.spr_id    = SPR_SPSR_EL1;
                    end
                endcase
            end

            I_MRS: begin
                // C6.2.194 Move System Register allows the PE to read an AArch64 System register into a general-purpose register.
                uop.is_privileged = 1'b1;
                uop.is_mrs        = 1'b1;
                uop.fu_select     = FU_LOGIC;
                uop.fu_op         = OP_MOV;
                uop.rd            = instr[4:0];
                uop.r_dest_valid  = 1'b1;
                uop.spr_id        = decoded_spr_id;
            end

            I_MSR: begin
                // C6.2.196 Move general-purpose register to System Register allows the PE to write an AArch64 System register from a general-purpose register.
                // At commit time, check for terminate written to ACTLR_EL1 (extra credit: low power state here)
                uop.is_privileged = 1'b1;
                uop.is_msr        = 1'b1;
                uop.fu_select     = FU_LOGIC;
                uop.fu_op         = OP_MOV;
                uop.rs1           = instr[4:0];
                uop.rs1_valid     = 1'b1;
                uop.spr_id        = decoded_spr_id;
            end

            I_SVC: begin
                /*
                C6.2.321 
                    Supervisor Call causes an exception to be taken to EL1.
                    On executing an SVC instruction, the PE records the exception as a Supervisor Call exception in ESR_ELx on
                    page K15-8606, using the EC value 0x15, and the value of the immediate argument.

                (Extra credit)
                At commit time:
                1. Save current PC to ELR_EL1
                2. Save current PSTATE to SPSR_EL1
                3. Switch to EL1
                4. Jump to the exception vector for synchronous exceptions (an offset from VBAR_EL1)

                */
                uop.is_svc    = 1'b1;
                uop.imm       = {48'd0, imm16};
                uop.imm_valid = 1'b1;
                uop.fu_select = FU_NONE;
                uop.fu_op     = OP_NOP;
            end

            // =============================================================
            // FLOATING-POINT
            // =============================================================


            I_F_LDUR: begin
              // AGU + RD
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_AGU;
                  uop.fu_op=OP_COMPUTE_ADDR;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.imm={{55{instr[20]}},instr[20:12]};
                  uop.imm_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                  uop.fu_select=FU_MEM;
                  uop.fu_op=OP_LOAD;
                  uop.rd=instr[4:0];
                  uop.r_dest_valid=1'b1;
                end
              endcase
            end

            I_F_STUR: begin
              // AGU + WR
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_AGU;
                  uop.fu_op=OP_COMPUTE_ADDR;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.imm={{55{instr[20]}},instr[20:12]};
                  uop.imm_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                  uop.fu_select=FU_MEM;
                  uop.fu_op=OP_STORE;
                  uop.is_store=1'b1;
                  uop.rd=instr[4:0];
                  uop.r_dest_valid=1'b1;
                end
              endcase
            end

            I_FMOV: begin
              uop.fu_select=FU_LOGIC;
              uop.fu_op=OP_OR;
              uop.rd=instr[4:0];
              uop.r_dest_valid=1'b1;
              uop.rs1=5'b11111;
              uop.rs1_valid=1'b1;
              uop.rs2=Rn_field;
              uop.rs2_valid=1'b1;
            end

            I_FNEG: begin
              uop.fu_select=FU_LOGIC;
              uop.fu_op=OP_XOR;
              uop.rd=instr[4:0];
              uop.r_dest_valid=1'b1;
              uop.rs1=Rn_field;
              uop.rs1_valid=1'b1;
              uop.imm=64'h8000_0000_0000_0000;
              uop.imm_valid=1'b1;
            end

            I_FADD: begin
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_NAN_CHECK;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_FADD;
                  uop.rd=instr[4:0];
                  uop.r_dest_valid=1'b1;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                end
              endcase
            end

            I_FMUL: begin
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_NAN_CHECK;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_FMUL;
                  uop.rd=instr[4:0];
                  uop.r_dest_valid=1'b1;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                end
              endcase
            end

            I_FSUB: begin
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_NAN_CHECK;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                    uop.fu_select=FU_LOGIC;
                    uop.fu_op=OP_XOR;
                    uop.rd=instr[4:0];
                    uop.r_dest_valid=1'b1;
                    uop.rs1=RmField;
                    uop.rs1_valid=1'b1;
                    uop.imm=64'h8000_0000_0000_0000;
                    uop.imm_valid=1'b1;
                    uop.last_uop=1'b0;
                end
                2: begin
                    uop.fu_select=FU_FPU;
                    uop.fu_op=OP_FADD;
                    uop.rd=instr[4:0];
                    uop.r_dest_valid=1'b1;
                    uop.rs1=Rn_field;
                    uop.rs1_valid=1'b1;
                    uop.rs2=instr[4:0];
                    uop.rs2_valid=1'b1;
                end
              endcase
            end

            I_FCMP_RR: begin
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_NAN_CHECK;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_FCMP;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=RmField;
                  uop.rs2_valid=1'b1;
                  uop.sets_flags=1'b1;
                end
              endcase
            end

            I_FCMP_RI: begin
              case (uop_counter)
                0: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_NAN_CHECK;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=5'd31;
                  uop.rs2_valid=1'b1;
                  uop.last_uop=1'b0;
                end
                1: begin
                  uop.fu_select=FU_FPU;
                  uop.fu_op=OP_FCMP;
                  uop.rs1=Rn_field;
                  uop.rs1_valid=1'b1;
                  uop.rs2=5'd31;
                  uop.rs2_valid=1'b1;
                  uop.sets_flags=1'b1;
                end
              endcase
            end

            default: begin
            end
        endcase
    end

endmodule

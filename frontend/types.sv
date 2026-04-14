`timescale 1ns / 1ps

package frontend_types;

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
        OP_MOV,
        OP_COND_CHECK,
        OP_NOP
        // TODO: add more
    } fu_op_t; // which op to execute, depends on our fus

    typedef enum logic [2:0] {
        SPR_SP_EL0,
        SPR_ELR_EL1,
        SPR_SPSR_EL1,
        SPR_VBAR_EL1,
        SPR_ACTLR_EL1,
        SPR_INVALID
    } spr_t;

    typedef struct packed {
        fu_t          fu_select;
        fu_op_t       fu_op;
        logic [4:0]   rd;
        logic         r_dest_valid;
        logic [4:0]   rs1;
        logic         rs1_valid;
        logic [4:0]   rs2;
        logic         rs2_valid;
        logic [63:0]  imm;
        logic         imm_valid;
        logic         src1_is_pc;
        logic         reads_flags;
        logic         sets_flags;
        logic         first_uop;
        logic         last_uop;
        logic         is_sequential;
        logic         is_branch;
        logic         is_eret;
        logic         is_privileged;
        logic         is_svc;
        logic [3:0]   cond;
        spr_t         spr_id;
    } uop_t;

endpackage

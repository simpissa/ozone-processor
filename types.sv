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
        OP_SUB, // No micro op for sub, only add, have module convert subs to adds
        OP_MOV,
        OP_COND_CHECK,
        OP_NOP,
        OP_COMPUTE_ADDR,
        OP_LOAD,
        OP_STORE,
        OP_AND,
        OP_XOR,
        OP_OR,
        OP_LSL,
        OP_LSR,
        OP_ASR,
        OP_NAN_CHECK,
        OP_FADD,
        OP_FMUL,
        OP_FCMP
    } fu_op_t; // which op to execute, depends on our fus

    typedef enum logic [2:0] {
        SPR_SP_EL0,
        SPR_ELR_EL1,
        SPR_SPSR_EL1,
        SPR_VBAR_EL1,
        SPR_ACTLR_EL1,
        SPR_INVALID
    } spr_t; // special purpose register id

    localparam int unsigned ROB_TAG_W = 6;

    typedef struct packed {
        fu_t          fu_select;      // which functional unit handles this uop
        fu_op_t       fu_op;          // operation within that functional unit
        logic [4:0]   rd;             // destination register
        logic         r_dest_valid;   // uop writes rd
        logic [4:0]   rs1;            // source register 1
        logic         rs1_valid;      // whether rs1 is used
        logic [4:0]   rs2;            // source register 2
        logic         rs2_valid;      // whether rs2 is used
        logic [63:0]  imm;            // immediate
        logic         imm_valid;      // whether immediate is used
        logic         src1_is_pc;     // use pc instead of rs1
        logic         reads_flags;    // uop consumes NZCV
        logic         sets_flags;     // uop produces NZCV
        logic         first_uop;      // first uop of a multi-uop instruction
        logic         last_uop;       // last uop of a multi-uop instruction
        logic         is_sequential;  // depends on the previous uop's result
        logic         is_branch;      // instruction is a branch
        logic         is_eret;        // instruction is ERET
        logic         is_privileged;  // instruction is privileged (EL1 only)
        logic         is_svc;         // instruction is SVC
        logic [3:0]   cond;           // condition code (for B.cond)
        spr_t         spr_id;         // special purpose register id
    } uop_t;

    typedef struct packed {
        fu_t                fu_select;
        fu_op_t             fu_op;
        logic [ROB_TAG_W-1:0] dest_tag;
        logic [63:0]        src1_value;
        logic [ROB_TAG_W-1:0] src1_tag;
        logic               src1_ready;
        logic [63:0]        src2_value;
        logic [ROB_TAG_W-1:0] src2_tag;
        logic               src2_ready;
        logic [63:0]        imm;
        logic               imm_valid;
        logic [3:0]         cond;
    } issue_payload_t;

endpackage

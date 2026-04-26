`timescale 1ns / 1ps

import types::*;

module core_backend (
    input  logic        clk,
    input  logic        rstN,

    input  logic        valid_in,
    output logic        ready_out,
    input  uop_t        uop_in,
    input  logic [63:0] pc_in,
    input  logic        pred_taken_in,
    input  logic [63:0] pred_target_in,

    output logic        flush,
    output logic [63:0] redirect_pc,
    output logic        terminate,

    output logic        brResolveValid,
    output logic        brResolveIsBranch,
    output logic        brResolveIsConditional,
    output logic [63:0] brResolvePC,
    output logic        brResolveTaken,
    output logic [63:0] brResolveTarget,

    output logic [63:0] ttbr0_el1,
    output logic        el_out,

    output logic        dmem_load_valid,
    output logic [47:0] dmem_load_vaddr,
    output logic [ROB_TAG_W-1:0] dmem_load_id,
    input  logic        dmem_load_ready,
    input  logic        dmem_load_received,
    input  logic        dmem_load_resp_valid,
    input  logic [ROB_TAG_W-1:0] dmem_load_resp_id,
    input  logic [63:0] dmem_load_resp_data,
    input  logic        dmem_load_fault_valid,
    input  logic [ROB_TAG_W-1:0] dmem_load_fault_id,

    output logic        dmem_store_valid,
    output logic [47:0] dmem_store_vaddr,
    output logic [63:0] dmem_store_value,
    input  logic        dmem_store_ready
);

    logic rst;
    assign rst = !rstN;

    issue_payload_t rename_payload;
    issue_payload_t issue_payload_bus;
    logic rename_valid;
    logic issue_ready_to_rename;

    logic rob_alloc_valid;
    logic [4:0] rob_dest_reg;
    logic rob_dest_valid;
    logic rob_dest_is_fp;
    logic [63:0] rob_pc;
    logic rob_is_branch;
    logic rob_is_conditional;
    logic rob_is_store;
    logic rob_pred_taken;
    logic [63:0] rob_pred_target;
    logic rob_first_uop;
    logic rob_last_uop;
    logic rob_is_eret;
    logic rob_is_msr;
    logic rob_is_mrs;
    logic rob_is_privileged;
    logic rob_is_svc;
    logic rob_sets_flags;
    spr_t rob_spr_id;
    logic [63:0] rob_exception_pc;
    logic rob_exception_el;
    logic rob_alloc_self_ready;
    logic rob_alloc_exception;
    logic [3:0] rob_alloc_exception_code;
    logic [ROB_TAG_W-1:0] rob_tag;
    logic rob_ready;

    logic commit_gpr_valid;
    logic [4:0] commit_gpr_rd;
    logic [63:0] commit_gpr_value;
    logic [ROB_TAG_W-1:0] commit_tag;
    logic commit_fp_valid;
    logic [4:0] commit_fp_rd;
    logic [63:0] commit_fp_value;
    logic commit_flags_valid;
    logic [3:0] commit_flags_value;
    logic commit_spr_valid;
    spr_t commit_spr_id;
    logic [63:0] commit_spr_value;
    logic commit_exc_elr_valid;
    logic [63:0] commit_exc_elr_value;
    logic commit_exc_spsr_valid;
    logic [63:0] commit_exc_spsr_value;
    logic commit_exc_esr_valid;
    logic [63:0] commit_exc_esr_value;
    logic commit_is_exception;
    logic commit_is_eret;
    logic [3:0] commit_exception_code;
    logic [63:0] commit_exception_pc;
    logic commit_store;
    logic [ROB_TAG_W-1:0] commit_store_tag;

    logic src1_lookup_valid;
    logic [ROB_TAG_W-1:0] src1_lookup_tag;
    logic src1_lookup_flags;
    logic src1_lookup_ready;
    logic [63:0] src1_lookup_value;
    logic src2_lookup_valid;
    logic [ROB_TAG_W-1:0] src2_lookup_tag;
    logic src2_lookup_flags;
    logic src2_lookup_ready;
    logic [63:0] src2_lookup_value;

    logic [3:0] flags_out;
    logic [63:0] vbar_el1;
    logic [63:0] elr_el1;

    fu_result_t cdb_result;
    fu_result_t [5:0] fu_results;
    logic [5:0] fu_grant;

    logic alu_issue_valid;
    logic alu_issue_ready;
    logic shifter_issue_valid;
    logic shifter_issue_ready;
    logic logic_issue_valid;
    logic logic_issue_ready;
    logic agu_issue_valid;
    logic agu_issue_ready;
    logic fpu_issue_valid;
    logic fpu_issue_ready;
    logic mem_issue_valid;
    logic mem_issue_ready;

    logic alu_rs_valid;
    logic alu_exec_ready;
    logic [63:0] alu_arg1;
    logic [63:0] alu_arg2;
    logic [ROB_TAG_W-1:0] alu_tag;
    logic alu_should_output;
    logic alu_set_flags;
    logic alu_src2_valid;
    logic [3:0] alu_cond;
    logic [63:0] alu_imm;
    fu_op_t alu_op;

    logic shifter_rs_valid;
    logic shifter_exec_ready;
    logic [63:0] shifter_arg1;
    logic [63:0] shifter_arg2;
    logic [ROB_TAG_W-1:0] shifter_tag;
    logic shifter_should_output;
    fu_op_t shifter_op;

    logic logic_rs_valid;
    logic logic_exec_ready;
    logic [63:0] logic_arg1;
    logic [63:0] logic_arg2;
    logic [ROB_TAG_W-1:0] logic_tag;
    logic logic_should_output;
    logic logic_set_flags;
    fu_op_t logic_op;

    logic agu_rs_valid;
    logic agu_exec_ready;
    logic [63:0] agu_addr;
    logic [63:0] agu_imm;
    logic [ROB_TAG_W-1:0] agu_tag;

    logic fpu_wb_valid;
    logic [ROB_TAG_W-1:0] fpu_wb_tag;
    logic [63:0] fpu_wb_value;
    logic [4:0] fpu_wb_fflags;
    logic fpu_wb_flags_valid;
    logic fpu_busy;

    logic lq_ready;
    logic sq_ready;
    logic sq_query_valid;
    logic [47:0] sq_query_addr;
    logic [ROB_TAG_W-1:0] sq_query_id;
    logic [ROB_TAG_W-1:0] sq_query_age;
    logic sq_forward_valid;
    logic [63:0] sq_forward_data;
    logic sq_conflict;
    logic sq_miss;
    logic sq_found;
    logic sq_resolved;
    logic [ROB_TAG_W-1:0] lq_head_age;
    logic lq_head_valid;
    logic load_complete_valid;
    logic [ROB_TAG_W-1:0] load_complete_id;
    logic [63:0] load_complete_data;
    logic load_complete_exception;
    logic store_complete_pending;
    logic [ROB_TAG_W-1:0] store_complete_tag;
    logic DBG;

    initial begin
        if (!$value$plusargs("BDEBUG=%b", DBG)) begin
            DBG = 1'b0;
        end
    end

    assign mem_issue_ready = (issue_payload_bus.fu_op == OP_LOAD)  ? lq_ready :
                             (issue_payload_bus.fu_op == OP_STORE) ? sq_ready : 1'b0;

    rename i_rename (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .uop(uop_in),
        .pc(pc_in),
        .el_out(el_out),
        .flags_out(flags_out),
        .spr_ttbr0_el1_out(ttbr0_el1),
        .spr_vbar_el1_out(vbar_el1),
        .spr_elr_el1_out(elr_el1),
        .valid_out(rename_valid),
        .ready_in(issue_ready_to_rename),
        .pred_taken(pred_taken_in),
        .pred_target(pred_target_in),
        .rob_alloc_valid(rob_alloc_valid),
        .rob_dest_reg(rob_dest_reg),
        .rob_dest_valid(rob_dest_valid),
        .rob_dest_is_fp(rob_dest_is_fp),
        .rob_pc(rob_pc),
        .rob_is_branch(rob_is_branch),
        .rob_is_conditional(rob_is_conditional),
        .rob_is_store(rob_is_store),
        .rob_pred_taken(rob_pred_taken),
        .rob_pred_target(rob_pred_target),
        .rob_first_uop(rob_first_uop),
        .rob_last_uop(rob_last_uop),
        .rob_is_eret(rob_is_eret),
        .rob_is_msr(rob_is_msr),
        .rob_is_mrs(rob_is_mrs),
        .rob_is_privileged(rob_is_privileged),
        .rob_is_svc(rob_is_svc),
        .rob_sets_flags(rob_sets_flags),
        .rob_spr_id(rob_spr_id),
        .rob_exception_pc(rob_exception_pc),
        .rob_exception_el(rob_exception_el),
        .rob_alloc_self_ready(rob_alloc_self_ready),
        .rob_alloc_exception(rob_alloc_exception),
        .rob_alloc_exception_code(rob_alloc_exception_code),
        .rob_tag(rob_tag),
        .rob_ready(rob_ready),
        .rob_commit_gpr_valid(commit_gpr_valid),
        .rob_commit_tag(commit_tag),
        .rob_commit_gpr_rd(commit_gpr_rd),
        .rob_commit_gpr_value(commit_gpr_value),
        .rob_commit_fp_valid(commit_fp_valid),
        .rob_commit_fp_rd(commit_fp_rd),
        .rob_commit_fp_value(commit_fp_value),
        .rob_commit_flags_valid(commit_flags_valid),
        .rob_commit_flags_value(commit_flags_value),
        .rob_commit_spr_valid(commit_spr_valid),
        .rob_commit_spr_id(commit_spr_id),
        .rob_commit_spr_value(commit_spr_value),
        .rob_commit_exc_elr_valid(commit_exc_elr_valid),
        .rob_commit_exc_elr_value(commit_exc_elr_value),
        .rob_commit_exc_spsr_valid(commit_exc_spsr_valid),
        .rob_commit_exc_spsr_value(commit_exc_spsr_value),
        .rob_commit_exc_esr_valid(commit_exc_esr_valid),
        .rob_commit_exc_esr_value(commit_exc_esr_value),
        .rob_commit_is_exception(commit_is_exception),
        .rob_commit_is_eret(commit_is_eret),
        .rob_src1_lookup_valid(src1_lookup_valid),
        .rob_src1_lookup_tag(src1_lookup_tag),
        .rob_src1_lookup_flags(src1_lookup_flags),
        .rob_src1_lookup_hit_ready(src1_lookup_ready),
        .rob_src1_lookup_value(src1_lookup_value),
        .rob_src2_lookup_valid(src2_lookup_valid),
        .rob_src2_lookup_tag(src2_lookup_tag),
        .rob_src2_lookup_flags(src2_lookup_flags),
        .rob_src2_lookup_hit_ready(src2_lookup_ready),
        .rob_src2_lookup_value(src2_lookup_value),
        .out_payload(rename_payload)
    );

    rob i_rob (
        .clk(clk),
        .rst(rst),
        .alloc_valid(rob_alloc_valid),
        .ready_out(rob_ready),
        .alloc_tag(rob_tag),
        .pc_in(rob_pc),
        .dest_reg(rob_dest_reg),
        .dest_valid(rob_dest_valid),
        .dest_is_fp(rob_dest_is_fp),
        .is_branch_in(rob_is_branch),
        .is_conditional_in(rob_is_conditional),
        .is_store_in(rob_is_store),
        .is_eret_in(rob_is_eret),
        .is_svc_in(rob_is_svc),
        .is_msr_in(rob_is_msr),
        .is_mrs_in(rob_is_mrs),
        .is_privileged_in(rob_is_privileged),
        .sets_flags_in(rob_sets_flags),
        .spr_id_in(rob_spr_id),
        .exception_pc_in(rob_exception_pc),
        .exception_el_in(rob_exception_el),
        .first_uop_in(rob_first_uop),
        .last_uop_in(rob_last_uop),
        .pred_target(rob_pred_target),
        .pred_taken(rob_pred_taken),
        .alloc_self_ready(rob_alloc_self_ready),
        .alloc_exception_in(rob_alloc_exception),
        .alloc_exception_code_in(rob_alloc_exception_code),
        .src1_lookup_valid(src1_lookup_valid),
        .src1_lookup_tag(src1_lookup_tag),
        .src1_lookup_flags(src1_lookup_flags),
        .src1_lookup_hit_ready(src1_lookup_ready),
        .src1_lookup_value(src1_lookup_value),
        .src2_lookup_valid(src2_lookup_valid),
        .src2_lookup_tag(src2_lookup_tag),
        .src2_lookup_flags(src2_lookup_flags),
        .src2_lookup_hit_ready(src2_lookup_ready),
        .src2_lookup_value(src2_lookup_value),
        .cdb_result(cdb_result),
        .commit_gpr_valid(commit_gpr_valid),
        .commit_gpr_rd(commit_gpr_rd),
        .commit_gpr_value(commit_gpr_value),
        .commit_tag(commit_tag),
        .commit_fp_valid(commit_fp_valid),
        .commit_fp_rd(commit_fp_rd),
        .commit_fp_value(commit_fp_value),
        .commit_spr_valid(commit_spr_valid),
        .commit_spr_id(commit_spr_id),
        .commit_spr_value(commit_spr_value),
        .commit_exc_elr_valid(commit_exc_elr_valid),
        .commit_exc_elr_value(commit_exc_elr_value),
        .commit_exc_spsr_valid(commit_exc_spsr_valid),
        .commit_exc_spsr_value(commit_exc_spsr_value),
        .commit_exc_esr_valid(commit_exc_esr_valid),
        .commit_exc_esr_value(commit_exc_esr_value),
        .commit_flags_valid(commit_flags_valid),
        .commit_flags_value(commit_flags_value),
        .commit_store(commit_store),
        .commit_store_tag(commit_store_tag),
        .redirect_pc(redirect_pc),
        .commit_is_eret(commit_is_eret),
        .commit_is_exception(commit_is_exception),
        .commit_exception_code(commit_exception_code),
        .commit_exception_pc(commit_exception_pc),
        .commit_terminate(terminate),
        .resolveValid(brResolveValid),
        .resolveIsBranch(brResolveIsBranch),
        .resolveIsConditional(brResolveIsConditional),
        .resolvePC(brResolvePC),
        .resolveTaken(brResolveTaken),
        .resolveTarget(brResolveTarget),
        .spr_vbar_el1(vbar_el1),
        .spr_elr_el1(elr_el1),
        .current_flags_in(flags_out),
        .flush(flush),
        .num_entries(),
        .full(),
        .empty()
    );

    issue i_issue (
        .flush(flush),
        .valid_in(rename_valid),
        .ready_out(issue_ready_to_rename),
        .in_payload(rename_payload),
        .issue_payload(issue_payload_bus),
        .alu_issue_valid(alu_issue_valid),
        .alu_issue_ready(alu_issue_ready),
        .shifter_issue_valid(shifter_issue_valid),
        .shifter_issue_ready(shifter_issue_ready),
        .logic_issue_valid(logic_issue_valid),
        .logic_issue_ready(logic_issue_ready),
        .agu_issue_valid(agu_issue_valid),
        .agu_issue_ready(agu_issue_ready),
        .fpu_issue_valid(fpu_issue_valid),
        .fpu_issue_ready(fpu_issue_ready),
        .mem_issue_valid(mem_issue_valid),
        .mem_issue_ready(mem_issue_ready)
    );

    alu_rs i_alu_rs (
        .clk(clk),
        .rstN(rstN),
        .flush(flush),
        .issueValid(alu_issue_valid),
        .issueReady(alu_issue_ready),
        .payload_bus(issue_payload_bus),
        .cdb_out(cdb_result),
        .valid_out(alu_rs_valid),
        .ready_in(alu_exec_ready),
        .arg1(alu_arg1),
        .arg2(alu_arg2),
        .tag(alu_tag),
        .should_output(alu_should_output),
        .set_flags(alu_set_flags),
        .src2_valid(alu_src2_valid),
        .cond(alu_cond),
        .imm(alu_imm),
        .op(alu_op)
    );

    alu i_alu (
        .clk(clk),
        .rstN(rstN),
        .flush(flush),
        .valid_in(alu_rs_valid),
        .ready_out(alu_exec_ready),
        .arg1(alu_arg1),
        .arg2(alu_arg2),
        .tag(alu_tag),
        .should_output(alu_should_output),
        .set_flags(alu_set_flags),
        .src2_valid(alu_src2_valid),
        .cond(alu_cond),
        .imm(alu_imm),
        .op(alu_op),
        .bus_in(cdb_result),
        .bus_out(fu_results[FU_ALU])
    );

    shifter_rs i_shifter_rs (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(shifter_issue_valid),
        .ready_out(shifter_issue_ready),
        .in(issue_payload_bus),
        .bus(cdb_result),
        .valid_out(shifter_rs_valid),
        .ready_in(shifter_exec_ready),
        .arg1(shifter_arg1),
        .arg2(shifter_arg2),
        .dst_tag(shifter_tag),
        .should_output(shifter_should_output),
        .op(shifter_op)
    );

    shifter i_shifter (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(shifter_rs_valid),
        .ready_out(shifter_exec_ready),
        .arg1(shifter_arg1),
        .arg2(shifter_arg2),
        .tag(shifter_tag),
        .should_output(shifter_should_output),
        .opcode(shifter_op),
        .bus_in(cdb_result),
        .bus_out(fu_results[FU_SHIFTER])
    );

    lu_rs i_logic_rs (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(logic_issue_valid),
        .ready_out(logic_issue_ready),
        .in(issue_payload_bus),
        .bus(cdb_result),
        .valid_out(logic_rs_valid),
        .ready_in(logic_exec_ready),
        .arg1(logic_arg1),
        .arg2(logic_arg2),
        .dst_tag(logic_tag),
        .should_output(logic_should_output),
        .set_flags(logic_set_flags),
        .op(logic_op)
    );

    lu i_logic (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(logic_rs_valid),
        .ready_out(logic_exec_ready),
        .arg1(logic_arg1),
        .arg2(logic_arg2),
        .tag(logic_tag),
        .should_output(logic_should_output),
        .set_flags(logic_set_flags),
        .opcode(logic_op),
        .bus_in(cdb_result),
        .bus_out(fu_results[FU_LOGIC])
    );

    agu_rs i_agu_rs (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(agu_issue_valid),
        .ready_out(agu_issue_ready),
        .in(issue_payload_bus),
        .bus(cdb_result),
        .valid_out(agu_rs_valid),
        .ready_in(agu_exec_ready),
        .addr(agu_addr),
        .imm(agu_imm),
        .dst_tag(agu_tag)
    );

    agu i_agu (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(agu_rs_valid),
        .ready_out(agu_exec_ready),
        .base_addr(agu_addr),
        .imm(agu_imm),
        .dst_tag(agu_tag),
        .bus_in(cdb_result),
        .bus_out(fu_results[FU_AGU])
    );

    backend i_fpu_backend (
        .clk(clk),
        .rstN(rstN),
        .flush(flush),
        .issueValid(fpu_issue_valid),
        .issueReady(fpu_issue_ready),
        .issueFuSelect(issue_payload_bus.fu_select),
        .issueFuOp(issue_payload_bus.fu_op),
        .issueSrc1(issue_payload_bus.src1_value),
        .issueSrc1Ready(issue_payload_bus.src1_ready),
        .issueSrc1Tag(issue_payload_bus.src1_tag),
        .issueSrc2(issue_payload_bus.src2_value),
        .issueSrc2Ready(issue_payload_bus.src2_ready),
        .issueSrc2Tag(issue_payload_bus.src2_tag),
        .issueTag(issue_payload_bus.dest_tag),
        .cdbBroadcast(cdb_result),
        .wbValid(fpu_wb_valid),
        .wbReady(fu_grant[FU_FPU]),
        .wbTag(fpu_wb_tag),
        .wbValue(fpu_wb_value),
        .wbFflags(fpu_wb_fflags),
        .wbFlagsValid(fpu_wb_flags_valid),
        .fpuBusy(fpu_busy)
    );

    assign fu_results[FU_FPU] = '{
        valid: fpu_wb_valid,
        tag: fpu_wb_tag,
        value: fpu_wb_value,
        flags: fpu_wb_fflags[3:0],
        flags_valid: fpu_wb_flags_valid,
        exception: 1'b0,
        exception_code: EXC_CODE_NONE
    };

    load_queue i_load_queue (
        .clk(clk),
        .reset(rst),
        .cdb_i(cdb_result),
        .payload_valid_i(mem_issue_valid && (issue_payload_bus.fu_op == OP_LOAD)),
        .payload_i(issue_payload_bus),
        .payload_ready_o(lq_ready),
        .sq_query_valid(sq_query_valid),
        .sq_query_addr(sq_query_addr),
        .sq_query_id(sq_query_id),
        .sq_query_age(sq_query_age),
        .sq_forward_valid(sq_forward_valid),
        .sq_forward_data(sq_forward_data),
        .sq_conflict(sq_conflict),
        .sq_miss(sq_miss),
        .lq_head_age(lq_head_age),
        .lq_head_valid(lq_head_valid),
        .l1_req_valid(dmem_load_valid),
        .l1_req_vaddr(dmem_load_vaddr),
        .l1_req_id(dmem_load_id),
        .l1_req_ready(dmem_load_ready),
        .l1_req_received(dmem_load_received),
        .l1_resp_valid(dmem_load_resp_valid),
        .l1_resp_id(dmem_load_resp_id),
        .l1_resp_data(dmem_load_resp_data),
        .l1_fault_valid(dmem_load_fault_valid),
        .l1_fault_id(dmem_load_fault_id),
        .load_complete_valid(load_complete_valid),
        .load_complete_id(load_complete_id),
        .load_complete_data(load_complete_data),
        .load_complete_exception(load_complete_exception)
    );

    store_queue i_store_queue (
        .rst(rst),
        .flush(flush),
        .clk_in(clk),
        .cdb_i(cdb_result),
        .payload_valid_i(mem_issue_valid && (issue_payload_bus.fu_op == OP_STORE)),
        .payload_i(issue_payload_bus),
        .payload_ready_o(sq_ready),
        .search_addr(sq_query_addr),
        .load_age(sq_query_age),
        .found(sq_found),
        .resolved(sq_resolved),
        .search_value(sq_forward_data),
        .lq_head_age(lq_head_age),
        .lq_head_valid(lq_head_valid),
        .commit_valid(commit_store),
        .commit_tag(commit_store_tag),
        .write_vaddr(dmem_store_vaddr),
        .write_value(dmem_store_value),
        .ready_in(dmem_store_ready),
        .valid_out(dmem_store_valid)
    );

    assign sq_forward_valid = sq_found && sq_resolved;
    assign sq_conflict = sq_found && !sq_resolved;
    assign sq_miss = !sq_found;

    always_ff @(posedge clk) begin
        if (!rstN || flush) begin
            store_complete_pending <= 1'b0;
            store_complete_tag <= '0;
        end else begin
            if (mem_issue_valid && mem_issue_ready && (issue_payload_bus.fu_op == OP_STORE)) begin
                store_complete_pending <= 1'b1;
                store_complete_tag <= issue_payload_bus.dest_tag;
            end

            if (fu_grant[FU_MEM] && store_complete_pending && !load_complete_valid) begin
                store_complete_pending <= 1'b0;
            end
        end
    end

    always_comb begin
        fu_results[FU_MEM] = '0;
        if (load_complete_valid) begin
            fu_results[FU_MEM].valid = 1'b1;
            fu_results[FU_MEM].tag = load_complete_id;
            fu_results[FU_MEM].value = load_complete_data;
            fu_results[FU_MEM].exception = load_complete_exception;
            fu_results[FU_MEM].exception_code = load_complete_exception ? EXC_CODE_DATA : EXC_CODE_NONE;
        end else if (store_complete_pending) begin
            fu_results[FU_MEM].valid = 1'b1;
            fu_results[FU_MEM].tag = store_complete_tag;
            fu_results[FU_MEM].value = 64'd0;
        end
    end

    cdb i_cdb (
        .flush(flush),
        .fu_results(fu_results),
        .fu_grant(fu_grant),
        .cdb_out(cdb_result)
    );

    always_ff @(posedge clk) begin
        if (DBG && rstN && valid_in && !ready_out) begin
            $display("Backend stall: pc=%016x fu=%0d op=%0d rob_ready=%0b rename_valid=%0b issue_ready=%0b lq_ready=%0b sq_ready=%0b mem_issue_ready=%0b alu_ready=%0b logic_ready=%0b agu_ready=%0b fu_valid=%06b grant=%06b",
                     pc_in, uop_in.fu_select, uop_in.fu_op, rob_ready, rename_valid,
                     issue_ready_to_rename, lq_ready, sq_ready, mem_issue_ready,
                     alu_issue_ready, logic_issue_ready, agu_issue_ready,
                     {fu_results[5].valid, fu_results[4].valid, fu_results[3].valid, fu_results[2].valid, fu_results[1].valid, fu_results[0].valid},
                     fu_grant);
        end
        if (DBG && rstN && cdb_result.valid) begin
            $display("CDB: tag=%0d value=%016x flags=%0h exception=%0b", cdb_result.tag, cdb_result.value, cdb_result.flags, cdb_result.exception);
        end
        if (DBG && rstN && dmem_load_valid) begin
            $display("DMEM load: id=%0d vaddr=%012x ready=%0b received=%0b resp_valid=%0b",
                     dmem_load_id, dmem_load_vaddr, dmem_load_ready, dmem_load_received, dmem_load_resp_valid);
        end
        if (DBG && rstN && dmem_store_valid) begin
            $display("DMEM store: vaddr=%012x value=%016x ready=%0b",
                     dmem_store_vaddr, dmem_store_value, dmem_store_ready);
        end
    end

endmodule

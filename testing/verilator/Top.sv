`timescale 1ns / 1ps

import types::*;

// Verilator wrapper around the ozone processor. Exposes the three real
// memory channels (imem, itlb_mem, dmem) plus committed architectural state
// to the C++ testbench, which serves memory from a shared-memory region.
module Top (
    input  logic        clk,
    input  logic        reset,         // active high
    input  logic [63:0] startPC,

    // imem: 64B line read, paddr from frontend iTLB
    output logic         imem_req_valid,
    output logic [29:0]  imem_req_addr,
    input  logic         imem_resp_valid,
    input  logic [511:0] imem_resp_rdata,

    // itlb_mem: 64B line read for page table walks
    output logic         itlb_req_valid,
    output logic [29:0]  itlb_req_addr,
    input  logic         itlb_resp_valid,
    input  logic [511:0] itlb_resp_rdata,

    // dmem load (vaddr, must be translated by testbench)
    output logic                 dmem_load_valid,
    output logic [47:0]          dmem_load_vaddr,
    output logic [ROB_TAG_W-1:0] dmem_load_id,
    input  logic                 dmem_load_ready,
    input  logic                 dmem_load_received,
    input  logic                 dmem_load_resp_valid,
    input  logic [ROB_TAG_W-1:0] dmem_load_resp_id,
    input  logic [63:0]          dmem_load_resp_data,

    // dmem store (vaddr, fire-and-forget)
    output logic         dmem_store_valid,
    output logic [47:0]  dmem_store_vaddr,
    output logic [63:0]  dmem_store_value,
    input  logic         dmem_store_ready,

    // status
    output logic         done,

    // architectural state, sampled from inside ozone via hierarchical refs
    output logic [63:0]  x_regs [0:30],
    output logic [63:0]  sprf   [0:7],
    output logic [3:0]   pstate_flags,
    output logic         el
);

    ozone proc (
        .clk(clk),
        .rstN(~reset),
        .startPC(startPC),
        .start(1'b1),

        .imem_rdata_i(imem_resp_rdata),
        .imem_ready_i(1'b1),
        .imem_valid_i(imem_resp_valid),
        .imem_valid_o(imem_req_valid),
        .imem_addr_o(imem_req_addr),

        .itlb_mem_rdata_i(itlb_resp_rdata),
        .itlb_mem_ready_i(1'b1),
        .itlb_mem_valid_i(itlb_resp_valid),
        .itlb_mem_valid_o(itlb_req_valid),
        .itlb_mem_addr_o(itlb_req_addr),

        .dmem_load_valid(dmem_load_valid),
        .dmem_load_vaddr(dmem_load_vaddr),
        .dmem_load_id(dmem_load_id),
        .dmem_load_ready(dmem_load_ready),
        .dmem_load_received(dmem_load_received),
        .dmem_load_resp_valid(dmem_load_resp_valid),
        .dmem_load_resp_id(dmem_load_resp_id),
        .dmem_load_resp_data(dmem_load_resp_data),

        .dmem_store_valid(dmem_store_valid),
        .dmem_store_vaddr(dmem_store_vaddr),
        .dmem_store_value(dmem_store_value),
        .dmem_store_ready(dmem_store_ready),

        .done(done)
    );

    generate
        for (genvar gi = 0; gi < 31; gi++) begin : g_xregs
            assign x_regs[gi] = proc.be.i_rename.gpr_arf[gi];
        end
        for (genvar gi = 0; gi < 8; gi++) begin : g_sprs
            assign sprf[gi] = proc.be.i_rename.sprf[gi];
        end
    endgenerate

    assign pstate_flags = proc.be.i_rename.flags_reg;
    assign el           = proc.be.i_rename.el_reg;

endmodule

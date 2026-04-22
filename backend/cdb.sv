`timescale 1ns / 1ps

import types::*;

module cdb #(
    parameter int unsigned NUM_FUS = 6
) (
    input  logic                      clk,
    input  logic                      rst,
    input  logic                      flush,

    input  fu_result_t [NUM_FUS-1:0]  fu_results,
    output logic [NUM_FUS-1:0]        fu_grant, // which FU the cdb is broadcasting this cycle, indexed by fu_t enum; FUs not being consumed should be stalled
    output fu_result_t                cdb_out // wired to rob + reservation stations
);

    always_comb begin
        fu_grant = '0;
        cdb_out  = '0;

        // arbitration: prioritize MEM -> FPU -> AGU -> ALU -> SHIFTER -> LOGIC
        if (fu_results[FU_MEM].valid) begin
            fu_grant[FU_MEM] = 1'b1;
            cdb_out          = fu_results[FU_MEM];
        end else if (fu_results[FU_FPU].valid) begin
            fu_grant[FU_FPU] = 1'b1;
            cdb_out          = fu_results[FU_FPU];
        end else if (fu_results[FU_AGU].valid) begin
            fu_grant[FU_AGU] = 1'b1;
            cdb_out          = fu_results[FU_AGU];
        end else if (fu_results[FU_ALU].valid) begin
            fu_grant[FU_ALU] = 1'b1;
            cdb_out          = fu_results[FU_ALU];
        end else if (fu_results[FU_SHIFTER].valid) begin
            fu_grant[FU_SHIFTER] = 1'b1;
            cdb_out              = fu_results[FU_SHIFTER];
        end else if (fu_results[FU_LOGIC].valid) begin
            fu_grant[FU_LOGIC] = 1'b1;
            cdb_out            = fu_results[FU_LOGIC];
        end
    end

endmodule

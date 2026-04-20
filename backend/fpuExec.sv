`timescale 1ns / 1ps

import frontend_types::*;

module fpuExecute #(
  parameter int unsigned TAG_W = 6
) (
  input logic clk,
  input logic rstN,
  input logic flush,

  // Issue side
  input logic reqValid,
  output logic reqReady,
  input fu_op_t reqOp,
  input logic [63:0] reqSrc1,
  input logic [63:0] reqSrc2,
  input logic [TAG_W-1:0] reqTag,

  // Writeback side
  output logic respValid,
  input logic respReady,
  output logic [TAG_W-1:0] respTag,
  output logic [63:0] respResult,
  output logic [4:0] respFflags,
  output logic busy
);

  logic [2:0][63:0] operandsI;
  fpnew_pkg::roundmode_e rndModeI;
  fpnew_pkg::operation_e opI;
  logic opModI;
  fpnew_pkg::fp_format_e srcFmtI;
  fpnew_pkg::fp_format_e dstFmtI;
  fpnew_pkg::int_format_e intFmtI;
  logic vectorialOpI;
  logic [0:0] simdMaskI;

  logic inValidI;
  logic inReadyO;
  logic [63:0] resultO;
  fpnew_pkg::status_t statusO;
  logic [TAG_W-1:0] tagO;
  logic outValidO;
  logic busyO;

  logic supportedOp;

  always_comb begin
    operandsI = '0;
    rndModeI = fpnew_pkg::RNE;
    opI = fpnew_pkg::ADD;
    opModI = 1'b0;
    srcFmtI = fpnew_pkg::FP64;
    dstFmtI = fpnew_pkg::FP64;
    intFmtI = fpnew_pkg::INT64;
    vectorialOpI = 1'b0;
    simdMaskI = 1'b1;
    supportedOp = 1'b1;

    case (reqOp)
      OP_NAN_CHECK: begin
        // Use SGNJ passthrough mode (RUP) as a non-destructive FP check stage.
        opI = fpnew_pkg::SGNJ;
        rndModeI = fpnew_pkg::RUP;
        operandsI[0] = reqSrc1;
        operandsI[1] = reqSrc2;
      end

      OP_FADD: begin
        // FPnew ADD uses op[1] + op[2].
        opI = fpnew_pkg::ADD;
        operandsI[1] = reqSrc1;
        operandsI[2] = reqSrc2;
      end

      OP_FMUL: begin
        opI = fpnew_pkg::MUL;
        operandsI[0] = reqSrc1;
        operandsI[1] = reqSrc2;
      end

      OP_FCMP: begin
        // FCMP maps to FP compare. RNE selects <= in fpnew CMP encoding.
        opI = fpnew_pkg::CMP;
        rndModeI = fpnew_pkg::RNE;
        operandsI[0] = reqSrc1;
        operandsI[1] = reqSrc2;
      end

      default: begin
        supportedOp = 1'b0;
      end
    endcase
  end

  assign inValidI = reqValid && supportedOp;
  assign reqReady = supportedOp && inReadyO;

  assign respValid = outValidO;
  assign respTag = tagO;
  assign respResult = resultO;
  assign respFflags = {statusO.NV, statusO.DZ, statusO.OF, statusO.UF, statusO.NX};
  assign busy = busyO;

  fpnew_top #(
    .Features (fpnew_pkg::RV64D),
    .Implementation (fpnew_pkg::DEFAULT_NOREGS),
    .TagType (logic [TAG_W-1:0])
  ) i_fpnew_top(
    .clk_i(clk),
    .rst_ni(rstN),
    .operands_i(operandsI),
    .rnd_mode_i(rndModeI),
    .op_i(opI),
    .op_mod_i(opModI),
    .src_fmt_i(srcFmtI),
    .dst_fmt_i(dstFmtI),
    .int_fmt_i(intFmtI),
    .vectorial_op_i(vectorialOpI),
    .simd_mask_i(simdMaskI),
    .tag_i(reqTag),
    .in_valid_i(inValidI),
    .in_ready_o(inReadyO),
    .flush_i(flush),
    .result_o(resultO),
    .status_o(statusO),
    .tag_o(tagO),
    .out_valid_o(outValidO),
    .out_ready_i(respReady),
    .busy_o(busyO),
    .early_valid_o()
  );

endmodule
`timescale 1ns / 1ps

import types::*;

module fpuRs #(
  parameter int unsigned RS_ENTRIES = 4,
  parameter int unsigned TAG_W = 6
) (
  input logic clk,
  input logic rstN,
  input logic flush,

  input logic issueValid,
  output logic issueReady,
  input fu_op_t issueOp,
  input logic [63:0] issueSrc1Value,
  input logic issueSrc1Ready,
  input logic [TAG_W-1:0] issueSrc1Tag,
  input logic [63:0] issueSrc2Value,
  input logic issueSrc2Ready,
  input logic [TAG_W-1:0] issueSrc2Tag,
  input logic [TAG_W-1:0] issueTag,

  input fu_result_t cdbIn,

  output logic execValid,
  input logic execReady,
  output fu_op_t execOp,
  output logic [63:0] execSrc1,
  output logic [63:0] execSrc2,
  output logic [TAG_W-1:0] execTag,

  output logic busy
);

  typedef struct packed {
    logic valid;
    fu_op_t op;
    logic [63:0] src1;
    logic src1Ready;
    logic [TAG_W-1:0] src1Tag;
    logic [63:0] src2;
    logic src2Ready;
    logic [TAG_W-1:0] src2Tag;
    logic [TAG_W-1:0] tag;
  } rs_entry_t;

  localparam int unsigned RS_PTR_W = (RS_ENTRIES > 1) ? $clog2(RS_ENTRIES) : 1;

  rs_entry_t rsMem [0:RS_ENTRIES-1];
  logic [RS_PTR_W-1:0] allocIdx;
  logic [RS_PTR_W-1:0] execIdx;
  logic allocFound;
  logic execFound;
  logic [RS_PTR_W:0] count;

  logic doPush;
  logic doPop;
  integer i;

  always_comb begin
    allocFound = 1'b0;
    allocIdx = '0;
    execFound = 1'b0;
    execIdx = '0;

    for (int j = 0; j < RS_ENTRIES; j = j + 1) begin
      if (!allocFound && !rsMem[j].valid) begin
        allocFound = 1'b1;
        allocIdx   = j[RS_PTR_W-1:0];
      end
      if (!execFound && rsMem[j].valid && rsMem[j].src1Ready && rsMem[j].src2Ready) begin
        execFound = 1'b1;
        execIdx   = j[RS_PTR_W-1:0];
      end
    end
  end

  assign issueReady = allocFound;
  assign execValid  = execFound;

  assign execOp = execFound ? rsMem[execIdx].op : OP_NOP;
  assign execSrc1 = execFound ? rsMem[execIdx].src1 : 64'd0;
  assign execSrc2 = execFound ? rsMem[execIdx].src2 : 64'd0;
  assign execTag = execFound ? rsMem[execIdx].tag : '0;

  assign doPush = issueValid && issueReady;
  assign doPop = execValid && execReady;

  assign busy = (count != 0);

  always_ff @(posedge clk) begin
    if (!rstN || flush) begin
      count <= '0;
      for (i = 0; i < RS_ENTRIES; i = i + 1) begin
        rsMem[i].valid <= 1'b0;
        rsMem[i].op <= OP_NOP;
        rsMem[i].src1 <= 64'd0;
        rsMem[i].src1Ready <= 1'b0;
        rsMem[i].src1Tag <= '0;
        rsMem[i].src2 <= 64'd0;
        rsMem[i].src2Ready <= 1'b0;
        rsMem[i].src2Tag <= '0;
        rsMem[i].tag <= '0;
      end
    end else begin
      // Wake up waiting operands from the shared CDB broadcast.
      if (cdbIn.valid) begin
        for (i = 0; i < RS_ENTRIES; i = i + 1) begin
          if (rsMem[i].valid) begin
            if (!rsMem[i].src1Ready && (rsMem[i].src1Tag == cdbIn.tag)) begin
              rsMem[i].src1 <= cdbIn.value;
              rsMem[i].src1Ready <= 1'b1;
            end
            if (!rsMem[i].src2Ready && (rsMem[i].src2Tag == cdbIn.tag)) begin
              rsMem[i].src2 <= cdbIn.value;
              rsMem[i].src2Ready <= 1'b1;
            end
          end
        end
      end

      if (doPush) begin
        rsMem[allocIdx].valid <= 1'b1;
        rsMem[allocIdx].op <= issueOp;
        rsMem[allocIdx].src1 <= issueSrc1Value;
        rsMem[allocIdx].src1Ready <= issueSrc1Ready || (cdbIn.valid && (issueSrc1Tag == cdbIn.tag));
        rsMem[allocIdx].src1Tag <= issueSrc1Tag;
        rsMem[allocIdx].src2 <= issueSrc2Value;
        rsMem[allocIdx].src2Ready <= issueSrc2Ready || (cdbIn.valid && (issueSrc2Tag == cdbIn.tag));
        rsMem[allocIdx].src2Tag <= issueSrc2Tag;
        rsMem[allocIdx].tag <= issueTag;

        if (!issueSrc1Ready && cdbIn.valid && (issueSrc1Tag == cdbIn.tag)) begin
          rsMem[allocIdx].src1 <= cdbIn.value;
        end
        if (!issueSrc2Ready && cdbIn.valid && (issueSrc2Tag == cdbIn.tag)) begin
          rsMem[allocIdx].src2 <= cdbIn.value;
        end
      end

      if (doPop) begin
        rsMem[execIdx].valid <= 1'b0;
      end

      unique case ({doPush, doPop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end

endmodule

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
  output logic respFlagsValid,
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
  logic [3:0] cmpFlags;

  function automatic logic [3:0] fcmp_flags(input logic [63:0] lhs, input logic [63:0] rhs);
    logic lhs_nan;
    logic rhs_nan;
    logic lhs_zero;
    logic rhs_zero;
    logic lhs_neg;
    logic rhs_neg;
    logic lhs_lt_rhs;
    begin
      lhs_nan  = (lhs[62:52] == 11'h7ff) && (lhs[51:0] != 52'd0);
      rhs_nan  = (rhs[62:52] == 11'h7ff) && (rhs[51:0] != 52'd0);
      lhs_zero = (lhs[62:0] == 63'd0);
      rhs_zero = (rhs[62:0] == 63'd0);
      lhs_neg  = lhs[63] && !lhs_zero;
      rhs_neg  = rhs[63] && !rhs_zero;

      if (lhs_nan || rhs_nan) begin
        fcmp_flags = 4'b0011; // unordered: C=1, V=1
      end else if ((lhs == rhs) || (lhs_zero && rhs_zero)) begin
        fcmp_flags = 4'b0110; // equal: Z=1, C=1
      end else begin
        if (lhs_neg != rhs_neg) begin
          lhs_lt_rhs = lhs_neg;
        end else if (!lhs_neg) begin
          lhs_lt_rhs = (lhs[62:0] < rhs[62:0]);
        end else begin
          lhs_lt_rhs = (lhs[62:0] > rhs[62:0]);
        end

        fcmp_flags = lhs_lt_rhs ? 4'b1000 : 4'b0010; // less or greater
      end
    end
  endfunction

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
    cmpFlags = fcmp_flags(reqSrc1, reqSrc2);

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
  assign respFflags = (reqOp == OP_FCMP) ? {1'b0, cmpFlags} :
                      {statusO.NV, statusO.DZ, statusO.OF, statusO.UF, statusO.NX};
  assign respFlagsValid = (reqOp == OP_FCMP) && outValidO;
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

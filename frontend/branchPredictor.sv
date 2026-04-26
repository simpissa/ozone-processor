`timescale 1ns / 1ps

module branchPredictor #(
	parameter int unsigned GHR_BITS = 8,
	parameter int unsigned BTB_ENTRIES = 64,
	parameter int unsigned BTB_INDEX_BITS = 6
) (
	input logic clk,
	input logic rstN,

	// Prediction query from fetch.
	input logic predReqValid,
	input logic [63:0] predReqPC,
	output logic predTaken,
	output logic [63:0] predTarget,

	// Branch resolution update from execute/commit.
	input logic resolveValid,
	input logic resolveIsBranch,
	input logic resolveIsConditional,
	input logic [63:0] resolvePC,
	input logic resolveTaken,
	input logic [63:0] resolveTarget
);

	localparam int unsigned PHT_ENTRIES = (1 << GHR_BITS);

	logic [GHR_BITS-1:0] ghr;
	logic [1:0] pht [0:PHT_ENTRIES-1];

	logic btbValid [0:BTB_ENTRIES-1];
	logic [63:0] btbTag [0:BTB_ENTRIES-1];
	logic [63:0] btbTgt [0:BTB_ENTRIES-1];

	logic [GHR_BITS-1:0] predPCIdx;
	logic [GHR_BITS-1:0] predGhrIdx;
	logic [GHR_BITS-1:0] predPhtIdx;
	logic [BTB_INDEX_BITS-1:0] predBtbIdx;

	logic [GHR_BITS-1:0] resPCIdx;
	logic [GHR_BITS-1:0] resGhrIdx;
	logic [GHR_BITS-1:0] resPhtIdx;
	logic [BTB_INDEX_BITS-1:0] resBtbIdx;

	logic [1:0] phtCtr;
	logic phtPredictTaken;
	logic btbHit;

	integer i;

	assign predPCIdx  = predReqPC[GHR_BITS+1:2];
	assign predGhrIdx = ghr;
	assign predPhtIdx = predPCIdx ^ predGhrIdx;
	assign predBtbIdx = predReqPC[BTB_INDEX_BITS+1:2];

	assign phtCtr = pht[predPhtIdx];
	assign phtPredictTaken = phtCtr[1];
	assign btbHit = btbValid[predBtbIdx] && (btbTag[predBtbIdx] == predReqPC);

	always_comb begin
		predTaken = 1'b0;
		predTarget = predReqPC + 64'd4;

		if (predReqValid && phtPredictTaken && btbHit) begin
			predTaken  = 1'b1;
			predTarget = btbTgt[predBtbIdx];
		end
	end

	assign resPCIdx  = resolvePC[GHR_BITS+1:2];
	assign resGhrIdx = ghr;
	assign resPhtIdx = resPCIdx ^ resGhrIdx;
	assign resBtbIdx = resolvePC[BTB_INDEX_BITS+1:2];

	always_ff @(posedge clk or negedge rstN) begin
		if (!rstN) begin
			ghr <= '0;

			for (i = 0; i < PHT_ENTRIES; i = i + 1)
				pht[i] = 2'b10; // weakly taken once a BTB entry exists

			for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
				btbValid[i] = 1'b0;
				btbTag[i]   = 64'd0;
				btbTgt[i]   = 64'd0;
			end
		end else if (resolveValid && resolveIsBranch) begin
			if (resolveIsConditional) begin
				if (resolveTaken) begin
					if (pht[resPhtIdx] != 2'b11)
						pht[resPhtIdx] <= pht[resPhtIdx] + 2'b01;
				end else begin
					if (pht[resPhtIdx] != 2'b00)
						pht[resPhtIdx] <= pht[resPhtIdx] - 2'b01;
				end

				if (GHR_BITS > 1)
					ghr <= {ghr[GHR_BITS-2:0], resolveTaken};
				else
					ghr <= {{(GHR_BITS-1){1'b0}}, resolveTaken};
			end

			if (resolveTaken) begin
				btbValid[resBtbIdx] <= 1'b1;
				btbTag[resBtbIdx] <= resolvePC;
				btbTgt[resBtbIdx] <= resolveTarget;
			end
		end
	end

endmodule

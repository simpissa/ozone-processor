module fetch (
	input logic clk,
	input logic rstN,
	input logic [63:0] predPC,
	input logic decodeReady,
	output logic [63:0] nextPC,
	output logic [31:0] instr,
	output logic [63:0] pc,
	output logic valid,
	output logic el
);

	// TODO: fetch 

	always_ff @(posedge clk or negedge rstN) begin
		if (!rstN)
			nextPC <= 64'd0;
		else if (decodeReady)
			nextPC <= predPC;
	end

	assign pc = nextPC;
	assign instr = 32'b0;
	assign valid = rstN;
	assign el = 1'b0;

endmodule
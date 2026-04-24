module ozone(
	input logic clk,
	input logic rstN,
	input logic [63:0] startPC,
	input logic start,
	// ...
);



	frontend fe(
		.clk(clk),
		.rstN(rstN),
		.brResolveValid(),
		.brResolveIsBranch(),
		.brResolveIsConditional(),
		.brResolvePC(),
		.brResolveTaken(),
		.brResolveTarget()
	);


	backend be(
		.clk(clk),
		.rstN(rstN)
	);



endmodule;
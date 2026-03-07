module load_queue #(
	parameter int VADDR_W = 48,
  parameter int PADDR_W = 30,
)(
	input  logic         clk,
	input  logic         reset,

  input logic[VADDR_W-1:0] v_addr,
  input logic valid,
  input logic[PADDR_W-1:0] tlb_addr,

  output logic l1ready,
  output logic miss,
  output logic data_out[63:0];

  input logic l2_data_in[63:0];
  // Will add on later
);

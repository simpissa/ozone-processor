
module load_queue #(
	parameter LQ_SIZE = 16
)(
	input  logic         clk,
	input  logic         reset,

	// Incoming trace operations
	input  logic         trace_valid,
	input  logic [2:0]   trace_op,
	input  logic [3:0]   trace_id,
	input  logic [47:0]  trace_vaddr,
	input  logic         trace_vaddr_is_valid,

	// Resolve updates (address/value resolution)
	input  logic         resolve_valid,
	input  logic [3:0]   resolve_id,
	input  logic [47:0]  resolve_vaddr,

	// Interface to Store Queue (for dependency checking / forwarding)
	output logic         sq_query_valid,
	output logic [47:0]  sq_query_addr,
	output logic [3:0]   sq_query_id,
	input  logic         sq_forward_valid,
	input  logic [63:0]  sq_forward_data,
	input  logic         sq_conflict,

	// Request to L1 data cache
	output logic         l1_req_valid,
	output logic [47:0]  l1_req_vaddr,
	output logic [3:0]   l1_req_id,
	input  logic         l1_req_ready,

	// Response from cache hierarchy
	input  logic         l1_resp_valid,
	input  logic [3:0]   l1_resp_id,
	input  logic [63:0]  l1_resp_data,

	// Completion output (load finished)
	output logic         load_complete_valid,
	output logic [3:0]   load_complete_id,
	output logic [63:0]  load_complete_data
);


module soc_system (
	clk_clk,
	commit_data_export,
	hps_to_fpga_handshake_readdata,
	hps_0_h2f_reset_reset_n,
	memory_mem_a,
	memory_mem_ba,
	memory_mem_ck,
	memory_mem_ck_n,
	memory_mem_cke,
	memory_mem_cs_n,
	memory_mem_ras_n,
	memory_mem_cas_n,
	memory_mem_we_n,
	memory_mem_reset_n,
	memory_mem_dq,
	memory_mem_dqs,
	memory_mem_dqs_n,
	memory_mem_odt,
	memory_mem_dm,
	memory_oct_rzqin,
	req_addr_export,
	req_ready_export,
	req_rw_export,
	req_valid_export,
	req_wdata_export,
	reset_reset_n,
	resp_rdata_export,
	resp_valid_export,
	trace_data_readdata,
	fpga_to_hps_handshake_export);	

	input		clk_clk;
	input	[127:0]	commit_data_export;
	output	[127:0]	hps_to_fpga_handshake_readdata;
	output		hps_0_h2f_reset_reset_n;
	output	[14:0]	memory_mem_a;
	output	[2:0]	memory_mem_ba;
	output		memory_mem_ck;
	output		memory_mem_ck_n;
	output		memory_mem_cke;
	output		memory_mem_cs_n;
	output		memory_mem_ras_n;
	output		memory_mem_cas_n;
	output		memory_mem_we_n;
	output		memory_mem_reset_n;
	inout	[31:0]	memory_mem_dq;
	inout	[3:0]	memory_mem_dqs;
	inout	[3:0]	memory_mem_dqs_n;
	output		memory_mem_odt;
	output	[3:0]	memory_mem_dm;
	input		memory_oct_rzqin;
	input	[31:0]	req_addr_export;
	output		req_ready_export;
	input		req_rw_export;
	inout		req_valid_export;
	input	[511:0]	req_wdata_export;
	input		reset_reset_n;
	output	[511:0]	resp_rdata_export;
	output		resp_valid_export;
	output	[127:0]	trace_data_readdata;
	input	[127:0]	fpga_to_hps_handshake_export;
endmodule

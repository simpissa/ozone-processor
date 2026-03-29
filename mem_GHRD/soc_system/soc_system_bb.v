
module soc_system (
	clk_clk,
	fpga_to_hps_handshake_export,
	hps_0_h2f_reset_reset_n,
	hps_to_fpga_handshake_readdata,
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
	sdram_req_addr_export,
	sdram_req_ready_export,
	sdram_req_rw_export,
	sdram_req_valid_export,
	sdram_req_wdata_export,
	reset_reset_n,
	sdram_resp_rdata_export,
	sdram_resp_valid_export,
	trace_data_readdata);	

	input		clk_clk;
	input	[127:0]	fpga_to_hps_handshake_export;
	output		hps_0_h2f_reset_reset_n;
	output	[127:0]	hps_to_fpga_handshake_readdata;
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
	input	[31:0]	sdram_req_addr_export;
	output		sdram_req_ready_export;
	input		sdram_req_rw_export;
	inout		sdram_req_valid_export;
	input	[511:0]	sdram_req_wdata_export;
	input		reset_reset_n;
	output	[511:0]	sdram_resp_rdata_export;
	output		sdram_resp_valid_export;
	output	[127:0]	trace_data_readdata;
endmodule

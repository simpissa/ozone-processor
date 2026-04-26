	soc_system u0 (
		.clk_clk                        (<connected-to-clk_clk>),                        //                   clk.clk
		.fpga_to_hps_handshake_export   (<connected-to-fpga_to_hps_handshake_export>),   // fpga_to_hps_handshake.export
		.hps_0_h2f_reset_reset_n        (<connected-to-hps_0_h2f_reset_reset_n>),        //       hps_0_h2f_reset.reset_n
		.hps_to_fpga_handshake_readdata (<connected-to-hps_to_fpga_handshake_readdata>), // hps_to_fpga_handshake.readdata
		.memory_mem_a                   (<connected-to-memory_mem_a>),                   //                memory.mem_a
		.memory_mem_ba                  (<connected-to-memory_mem_ba>),                  //                      .mem_ba
		.memory_mem_ck                  (<connected-to-memory_mem_ck>),                  //                      .mem_ck
		.memory_mem_ck_n                (<connected-to-memory_mem_ck_n>),                //                      .mem_ck_n
		.memory_mem_cke                 (<connected-to-memory_mem_cke>),                 //                      .mem_cke
		.memory_mem_cs_n                (<connected-to-memory_mem_cs_n>),                //                      .mem_cs_n
		.memory_mem_ras_n               (<connected-to-memory_mem_ras_n>),               //                      .mem_ras_n
		.memory_mem_cas_n               (<connected-to-memory_mem_cas_n>),               //                      .mem_cas_n
		.memory_mem_we_n                (<connected-to-memory_mem_we_n>),                //                      .mem_we_n
		.memory_mem_reset_n             (<connected-to-memory_mem_reset_n>),             //                      .mem_reset_n
		.memory_mem_dq                  (<connected-to-memory_mem_dq>),                  //                      .mem_dq
		.memory_mem_dqs                 (<connected-to-memory_mem_dqs>),                 //                      .mem_dqs
		.memory_mem_dqs_n               (<connected-to-memory_mem_dqs_n>),               //                      .mem_dqs_n
		.memory_mem_odt                 (<connected-to-memory_mem_odt>),                 //                      .mem_odt
		.memory_mem_dm                  (<connected-to-memory_mem_dm>),                  //                      .mem_dm
		.memory_oct_rzqin               (<connected-to-memory_oct_rzqin>),               //                      .oct_rzqin
		.reset_reset_n                  (<connected-to-reset_reset_n>),                  //                 reset.reset_n
		.sdram_req_addr_export          (<connected-to-sdram_req_addr_export>),          //        sdram_req_addr.export
		.sdram_req_ready_export         (<connected-to-sdram_req_ready_export>),         //       sdram_req_ready.export
		.sdram_req_rw_export            (<connected-to-sdram_req_rw_export>),            //          sdram_req_rw.export
		.sdram_req_valid_export         (<connected-to-sdram_req_valid_export>),         //       sdram_req_valid.export
		.sdram_req_wdata_export         (<connected-to-sdram_req_wdata_export>),         //       sdram_req_wdata.export
		.sdram_resp_rdata_export        (<connected-to-sdram_resp_rdata_export>),        //      sdram_resp_rdata.export
		.sdram_resp_valid_export        (<connected-to-sdram_resp_valid_export>),        //      sdram_resp_valid.export
		.trace_data_readdata            (<connected-to-trace_data_readdata>)             //            trace_data.readdata
	);


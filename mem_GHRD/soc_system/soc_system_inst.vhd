	component soc_system is
		port (
			clk_clk                        : in    std_logic                      := 'X';             -- clk
			commit_data_export             : in    std_logic_vector(127 downto 0) := (others => 'X'); -- export
			hps_to_fpga_handshake_readdata : out   std_logic_vector(127 downto 0);                    -- readdata
			hps_0_h2f_reset_reset_n        : out   std_logic;                                         -- reset_n
			memory_mem_a                   : out   std_logic_vector(14 downto 0);                     -- mem_a
			memory_mem_ba                  : out   std_logic_vector(2 downto 0);                      -- mem_ba
			memory_mem_ck                  : out   std_logic;                                         -- mem_ck
			memory_mem_ck_n                : out   std_logic;                                         -- mem_ck_n
			memory_mem_cke                 : out   std_logic;                                         -- mem_cke
			memory_mem_cs_n                : out   std_logic;                                         -- mem_cs_n
			memory_mem_ras_n               : out   std_logic;                                         -- mem_ras_n
			memory_mem_cas_n               : out   std_logic;                                         -- mem_cas_n
			memory_mem_we_n                : out   std_logic;                                         -- mem_we_n
			memory_mem_reset_n             : out   std_logic;                                         -- mem_reset_n
			memory_mem_dq                  : inout std_logic_vector(31 downto 0)  := (others => 'X'); -- mem_dq
			memory_mem_dqs                 : inout std_logic_vector(3 downto 0)   := (others => 'X'); -- mem_dqs
			memory_mem_dqs_n               : inout std_logic_vector(3 downto 0)   := (others => 'X'); -- mem_dqs_n
			memory_mem_odt                 : out   std_logic;                                         -- mem_odt
			memory_mem_dm                  : out   std_logic_vector(3 downto 0);                      -- mem_dm
			memory_oct_rzqin               : in    std_logic                      := 'X';             -- oct_rzqin
			req_addr_export                : in    std_logic_vector(31 downto 0)  := (others => 'X'); -- export
			req_ready_export               : out   std_logic;                                         -- export
			req_rw_export                  : in    std_logic                      := 'X';             -- export
			req_valid_export               : inout std_logic                      := 'X';             -- export
			req_wdata_export               : in    std_logic_vector(511 downto 0) := (others => 'X'); -- export
			reset_reset_n                  : in    std_logic                      := 'X';             -- reset_n
			resp_rdata_export              : out   std_logic_vector(511 downto 0);                    -- export
			resp_valid_export              : out   std_logic;                                         -- export
			trace_data_readdata            : out   std_logic_vector(127 downto 0);                    -- readdata
			fpga_to_hps_handshake_export   : in    std_logic_vector(127 downto 0) := (others => 'X')  -- export
		);
	end component soc_system;

	u0 : component soc_system
		port map (
			clk_clk                        => CONNECTED_TO_clk_clk,                        --                   clk.clk
			commit_data_export             => CONNECTED_TO_commit_data_export,             --           commit_data.export
			hps_to_fpga_handshake_readdata => CONNECTED_TO_hps_to_fpga_handshake_readdata, -- hps_to_fpga_handshake.readdata
			hps_0_h2f_reset_reset_n        => CONNECTED_TO_hps_0_h2f_reset_reset_n,        --       hps_0_h2f_reset.reset_n
			memory_mem_a                   => CONNECTED_TO_memory_mem_a,                   --                memory.mem_a
			memory_mem_ba                  => CONNECTED_TO_memory_mem_ba,                  --                      .mem_ba
			memory_mem_ck                  => CONNECTED_TO_memory_mem_ck,                  --                      .mem_ck
			memory_mem_ck_n                => CONNECTED_TO_memory_mem_ck_n,                --                      .mem_ck_n
			memory_mem_cke                 => CONNECTED_TO_memory_mem_cke,                 --                      .mem_cke
			memory_mem_cs_n                => CONNECTED_TO_memory_mem_cs_n,                --                      .mem_cs_n
			memory_mem_ras_n               => CONNECTED_TO_memory_mem_ras_n,               --                      .mem_ras_n
			memory_mem_cas_n               => CONNECTED_TO_memory_mem_cas_n,               --                      .mem_cas_n
			memory_mem_we_n                => CONNECTED_TO_memory_mem_we_n,                --                      .mem_we_n
			memory_mem_reset_n             => CONNECTED_TO_memory_mem_reset_n,             --                      .mem_reset_n
			memory_mem_dq                  => CONNECTED_TO_memory_mem_dq,                  --                      .mem_dq
			memory_mem_dqs                 => CONNECTED_TO_memory_mem_dqs,                 --                      .mem_dqs
			memory_mem_dqs_n               => CONNECTED_TO_memory_mem_dqs_n,               --                      .mem_dqs_n
			memory_mem_odt                 => CONNECTED_TO_memory_mem_odt,                 --                      .mem_odt
			memory_mem_dm                  => CONNECTED_TO_memory_mem_dm,                  --                      .mem_dm
			memory_oct_rzqin               => CONNECTED_TO_memory_oct_rzqin,               --                      .oct_rzqin
			req_addr_export                => CONNECTED_TO_req_addr_export,                --              req_addr.export
			req_ready_export               => CONNECTED_TO_req_ready_export,               --             req_ready.export
			req_rw_export                  => CONNECTED_TO_req_rw_export,                  --                req_rw.export
			req_valid_export               => CONNECTED_TO_req_valid_export,               --             req_valid.export
			req_wdata_export               => CONNECTED_TO_req_wdata_export,               --             req_wdata.export
			reset_reset_n                  => CONNECTED_TO_reset_reset_n,                  --                 reset.reset_n
			resp_rdata_export              => CONNECTED_TO_resp_rdata_export,              --            resp_rdata.export
			resp_valid_export              => CONNECTED_TO_resp_valid_export,              --            resp_valid.export
			trace_data_readdata            => CONNECTED_TO_trace_data_readdata,            --            trace_data.readdata
			fpga_to_hps_handshake_export   => CONNECTED_TO_fpga_to_hps_handshake_export    -- fpga_to_hps_handshake.export
		);


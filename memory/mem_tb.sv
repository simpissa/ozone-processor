`timescale 1ns / 1ps

module mem_tb ();

localparam int SDRAM_LATENCY = 3;
localparam int MAX_ARCH_ENTRIES = 16384;
localparam int TRACE_PRINT_LIMIT = 50;
localparam int TRACE_PROGRESS_INTERVAL = 1000;
localparam int TRACE_WAIT_TIMEOUT = 50000;
localparam string DEFAULT_TRACE_FILE = "mem-traces-v2/traces/dgemm3_lsq88.bin";
localparam int TRACE_LIMIT = 0; // 0 for full trace

logic clk_in;
logic reset;

logic trace_valid;
logic trace_ready;
logic [127:0] trace_data;

logic commit_ready;
logic commit_valid;
logic [47:0] commit_vaddr;
logic [63:0] commit_value;

logic sdram_req_valid;
logic sdram_req_ready;
logic sdram_req_rw;
logic [31:0] sdram_req_addr;
logic [511:0] sdram_req_wdata;
logic sdram_resp_valid;
logic [511:0] sdram_resp_rdata;
logic sdram_pending;
logic sdram_pending_rw;
logic [31:0] sdram_pending_addr;
logic [511:0] sdram_pending_wdata;
int sdram_cycles_left;

logic [511:0] sdram [0:1<<24];
logic [47:0] arch_addrs [0:MAX_ARCH_ENTRIES-1];
logic [63:0] arch_values [0:MAX_ARCH_ENTRIES-1];
logic [MAX_ARCH_ENTRIES-1:0] arch_valid;
int arch_entry_count;

assign sdram_req_ready = !sdram_pending;

task automatic print_arch_mem;
    logic [MAX_ARCH_ENTRIES-1:0] printed;
    int min_idx;
    begin
        for (int i = 0; i < MAX_ARCH_ENTRIES; i++) begin
            printed[i] = 1'b0;
        end
        if (arch_entry_count == 0) begin
            $display("RTL committed architectural memory state: none");
            return;
        end

        $display("RTL committed architectural memory state:");
        $display("%-14s | %-18s", "Address", "Value");
        $display("-----------------------------------------");

        for (int printed_count = 0; printed_count < arch_entry_count; printed_count++) begin
            min_idx = -1;
            for (int i = 0; i < MAX_ARCH_ENTRIES; i++) begin
                if (arch_valid[i] && !printed[i]) begin
                    if (min_idx == -1 || arch_addrs[i] < arch_addrs[min_idx]) begin
                        min_idx = i;
                    end
                end
            end

            printed[min_idx] = 1'b1;
            $display("0x%012h | 0x%016h", arch_addrs[min_idx], arch_values[min_idx]);
        end
    end
endtask

mem_top #(
    .PAGE_OFF_W(12),
    .VADDR_W(48),
    .PADDR_W(30),
    .TLB_ENTRIES(16),
    .ID_W(4),
    .LQ_SIZE(8),
    .SQ_SIZE(8)
) dut (
    .clk(clk_in),
    .rst(reset),
    .trace_valid(trace_valid),
    .trace_ready(trace_ready),
    .trace_data(trace_data),
    .sdram_req_valid(sdram_req_valid),
    .sdram_req_ready(sdram_req_ready),
    .sdram_req_rw(sdram_req_rw),
    .sdram_req_addr(sdram_req_addr),
    .sdram_req_wdata(sdram_req_wdata),
    .sdram_resp_valid(sdram_resp_valid),
    .sdram_resp_rdata(sdram_resp_rdata)
);

typedef enum logic [2:0] {
    OP_MEM_LOAD = 3'd0,
    OP_MEM_STORE = 3'd1,
    OP_MEM_RESOLVE = 3'd2,
    OP_TLB_FILL = 3'd4
} op_e;

initial begin
    clk_in = 0;
    // TODO: are we able to leave this high all the time?
    commit_ready = 1;
    forever begin
        #5 clk_in = ~clk_in;
    end
end

always @(posedge clk_in) begin
    int free_idx;
    bit found_match;

    if (reset) begin
        for (int i = 0; i < MAX_ARCH_ENTRIES; i++) begin
            arch_valid[i] = 1'b0;
        end
        arch_entry_count = 0;
    end else if (dut.l1_valid_out && dut.l1_req_ready) begin
        free_idx = -1;
        found_match = 0;

        for (int i = 0; i < MAX_ARCH_ENTRIES; i++) begin
            if (arch_valid[i] && arch_addrs[i] == dut.l1_write_vaddr) begin
                arch_values[i] = dut.l1_write_value;
                found_match = 1;
            end else if (!arch_valid[i] && free_idx == -1) begin
                free_idx = i;
            end
        end

        if (!found_match) begin
            if (free_idx == -1) begin
                $display("ERROR: architectural scoreboard full");
                $finish;
            end

            arch_valid[free_idx] = 1'b1;
            arch_addrs[free_idx] = dut.l1_write_vaddr;
            arch_values[free_idx] = dut.l1_write_value;
            arch_entry_count = arch_entry_count + 1;
        end
    end
end

always_ff @(posedge clk_in) begin
    int offset;

    if (reset) begin
        sdram_resp_valid <= 0;
        sdram_resp_rdata <= '0;
        sdram_pending <= 0;
        sdram_pending_rw <= 0;
        sdram_pending_addr <= '0;
        sdram_pending_wdata <= '0;
        sdram_cycles_left <= 0;
    end else begin
        sdram_resp_valid <= 0;

        if (!sdram_pending && sdram_req_valid && sdram_req_ready) begin
            sdram_pending <= 1;
            sdram_pending_rw <= sdram_req_rw;
            sdram_pending_addr <= sdram_req_addr;
            sdram_pending_wdata <= sdram_req_wdata;
            sdram_cycles_left <= SDRAM_LATENCY;
        end else if (sdram_pending) begin
            if (sdram_cycles_left > 0) begin
                sdram_cycles_left <= sdram_cycles_left - 1;
            end else begin
                offset = (sdram_pending_addr - 32'h20000000) / 64;

                if (!sdram_pending_rw) begin
                    sdram_resp_rdata <= sdram[offset];
                    sdram_resp_valid <= 1;
                end else begin
                    sdram[offset] <= sdram_pending_wdata;
                end

                sdram_pending <= 0;
            end
        end
    end
end

byte buffer [0:15];
logic [127:0] trace_line;

op_e trace_op;
logic [3:0] trace_id;
logic [47:0] trace_vaddr;
logic trace_vaddr_is_valid;
logic [29:0] trace_tlb_paddr;
logic [63:0] trace_value;
logic trace_value_is_valid;

string filename;
string op_name;

int fd;
int count = 0;
int trace_limit;

initial begin
    int drain_cycles;
    int quiet_cycles;
    int wait_cycles;
    reset = 1;
    @(negedge clk_in);
    reset = 0;
    @(negedge clk_in);
    filename = DEFAULT_TRACE_FILE;
    trace_limit = TRACE_LIMIT;
    if (!$value$plusargs("TRACE_FILE=%s", filename)) begin
        filename = DEFAULT_TRACE_FILE;
    end
    if (!$value$plusargs("TRACE_LIMIT=%d", trace_limit)) begin
        trace_limit = TRACE_LIMIT;
    end

    fd = $fopen(filename, "rb");
    if (fd == 0) begin
        $display("ERROR: Could not open trace file: %s", filename);
        $finish;
    end

    $display("\nReading trace from: %s", filename);
    $display("Printing first %0d trace records, then progress every %0d records.", TRACE_PRINT_LIMIT, TRACE_PROGRESS_INTERVAL);
    $display("------------------------------------------------------------------------------------------------------------------");
    $display("%-10s | %-3s | %-14s | %-2s | %-18s | %-3s | %-10s",
             "Op", "ID", "Vaddr", "VV", "Value", "VvV", "TLB Paddr");
    $display("------------------------------------------------------------------------------------------------------------------");
    while ($fread(buffer, fd) == 16) begin

        for (int i = 0; i < 16; ++i) begin
            trace_line[8 * i+: 8] = buffer[i];
        end

        trace_op = op_e'(trace_line[54:52]);
        trace_id = trace_line[51:48];
        trace_vaddr = trace_line[47:0];
        trace_vaddr_is_valid = trace_line[55];
        trace_tlb_paddr = trace_line[85:56];
        trace_value = trace_line[119:56];
        trace_value_is_valid = trace_line[120];

        case (trace_op)
            OP_MEM_LOAD: op_name = "LOAD";
            OP_MEM_STORE: op_name = "STORE";
            OP_MEM_RESOLVE: op_name = "RESOLVE";
            OP_TLB_FILL: op_name = "TLB_FILL";
            default: op_name = "UNKNOWN";
        endcase

        if (count < TRACE_PRINT_LIMIT) begin
            $write("%-10s | %2d  | 0x%012h | %1b  | 0x%016h | %1b  | ",
                op_name, trace_id, trace_vaddr, trace_vaddr_is_valid, trace_value, trace_value_is_valid);

            if (trace_op == OP_TLB_FILL)
                $display("0x%08h", trace_tlb_paddr);
            else
                $display("");
        end
        
        // This line needs to come before the while loop, otherwise the always_comb that updates
        // trace_ready will not run
        trace_data = trace_line;
        trace_valid = 1;
        wait_cycles = 0;
        #1
        while (!trace_ready) begin
            #1;
            wait_cycles++;
            if (wait_cycles == TRACE_WAIT_TIMEOUT) begin
                
                $finish;
            end
        end

            
        @(negedge clk_in);
        @(negedge clk_in);
        trace_valid = 0;

        count++;
        if (count <= TRACE_PRINT_LIMIT) begin
            $display("sdram vals: valid %b ready %b rw %b addr 0x%08x ", sdram_req_valid, sdram_req_ready, sdram_req_rw, sdram_req_addr);
            if (count == TRACE_PRINT_LIMIT) begin
                $display("... suppressing per-record trace output after %0d records ...", TRACE_PRINT_LIMIT);
            end
        end else if ((count % TRACE_PROGRESS_INTERVAL) == 0) begin
            $display("... processed %0d trace records ...", count);
        end

        if (trace_limit > 0 && count >= trace_limit) begin
            $display("... (Trace continues, truncated at %0d lines) ... ", trace_limit);
            break;
        end

    end

    quiet_cycles = 0;
    for (drain_cycles = 0; drain_cycles < 20000; drain_cycles++) begin
        @(negedge clk_in);

        if (!dut.trace_pending &&
            !dut.lq_head_valid &&
            !dut.lq.issue_storeq &&
            !dut.lq.issue_cache &&
            !dut.sq.valid_out &&
            !dut.l1_req_valid &&
            !sdram_pending) begin
            quiet_cycles++;
        end else begin
            quiet_cycles = 0;
        end

        if (quiet_cycles >= 20) begin
            break;
        end
    end

    print_arch_mem();
    $display("%d records read.", count);
    $fclose(fd);
    $finish;
    
end

endmodule

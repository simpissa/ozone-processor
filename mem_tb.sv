`timescale 1ns / 1ps

module mem_tb ();

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

logic avm_m0_read;
logic avm_m0_write;
logic [255:0] avm_m0_writedata;
logic [31:0] avm_m0_address;
logic [255:0] avm_m0_readdata;
logic avm_m0_readdatavalid;
logic [31:0] avm_m0_byteenable;
logic avm_m0_waitrequest;
logic [10:0] avm_m0_burstcount;

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
    /*
    .sdram_req_valid(sdram_req_valid),
    .sdram_req_ready(sdram_req_ready),
    .sdram_req_rw(sdram_req_rw),
    .sdram_req_addr(sdram_req_addr),
    .sdram_req_wdata(sdram_req_wdata),
    .sdram_resp_valid(sdram_resp_valid),
    .sdram_resp_rdata(sdram_resp_rdata),
    */
    .avm_m0_read(avm_m0_read),
    .avm_m0_write(avm_m0_write),
    .avm_m0_writedata(avm_m0_writedata),
    .avm_m0_address(avm_m0_address),
    .avm_m0_readdata(avm_m0_readdata),
    .avm_m0_readdatavalid(avm_m0_readdatavalid),
    .avm_m0_byteenable(avm_m0_byteenable),
    .avm_m0_waitrequest(avm_m0_waitrequest),
    .avm_m0_burstcount(avm_m0_burstcount)
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

initial begin
    if (!$value$plusargs("TRACE_FILE=%s", filename)) begin
        filename = "dgemm_tlb_trace.bin";
    end

    fd = $fopen(filename, "rb");
    if (fd == 0) begin
        $display("ERROR: Could not open trace file: %s", filename);
        $finish;
    end

    $display("\nReading trace from: %s", filename);
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

        $write("%-10s | %2d  | 0x%012h | %1b  | 0x%016h | %1b  | ",
            op_name, trace_id, trace_vaddr, trace_vaddr_is_valid, trace_value, trace_value_is_valid);

        if (trace_op == OP_TLB_FILL)
            $display("0x%08h", trace_tlb_paddr);
        else
            $display("");
        
        // This line needs to come before the while loop, otherwise the always_comb that updates
        // trace_ready will not run
        trace_data = trace_line;
        #1 // let propogate

        while (!trace_ready) begin
            trace_valid = 0;
        end
        trace_valid = 1;
        @(negedge clk_in);
        trace_valid = 0;

        count++;
        if (count >= 100) begin
            $display("... (Trace continues, truncated at 100 lines) ... ");
            break;
        end

    end
    $display("%d records read.", count);
    $fclose(fd);
    $finish;
    
end

endmodule

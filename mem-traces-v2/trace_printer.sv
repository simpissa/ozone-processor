`timescale 1ns/1ps

module trace_printer;

    typedef enum logic [2:0] {
        OP_MEM_LOAD    = 3'd0,
        OP_MEM_STORE   = 3'd1,
        OP_MEM_RESOLVE = 3'd2,
        OP_TLB_FILL    = 3'd4
    } op_e;

    // Use a byte array to read from file to avoid endianness issues with $fread into wide vectors
    byte buffer [0:15];
    logic [127:0] trace_line;

    // Map bytes to the logic vector (Little Endian: buffer[0] is bits 7:0)
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            trace_line[i*8 +: 8] = buffer[i];
        end
    end

    // Wire up the fields based on the spec
    op_e          trace_op             = op_e'(trace_line[54:52]);
    logic [3:0]   trace_id             = trace_line[51:48];
    logic [47:0]  trace_vaddr          = trace_line[47:0];
    logic         trace_vaddr_is_valid = trace_line[55];
    logic [29:0]  trace_tlb_paddr      = trace_line[85:56];
    logic [63:0]  trace_value          = trace_line[119:56];
    logic         trace_value_is_valid = trace_line[120];

    int fd;
    int count = 0;
    string filename;
    string op_name;

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
                 "Op", "ID", "VAddr", "VV", "Value", "VvV", "TLB PAddr");
        $display("------------------------------------------------------------------------------------------------------------------");

        while ($fread(buffer, fd) == 16) begin
            #1; // Allow always_comb to propagate

            case (trace_op)
                OP_MEM_LOAD:    op_name = "LOAD";
                OP_MEM_STORE:   op_name = "STORE";
                OP_MEM_RESOLVE: op_name = "RESOLVE";
                OP_TLB_FILL:    op_name = "TLB_FILL";
                default:        op_name = "UNKNOWN";
            endcase

            $write("%-10s | %2d  | 0x%012h | %1b  | 0x%016h | %1b   | ",
                   op_name, trace_id, trace_vaddr, trace_vaddr_is_valid,
                   trace_value, trace_value_is_valid);

            if (trace_op == OP_TLB_FILL)
                $display("0x%08h", trace_tlb_paddr);
            else
                $display("");

            count++;

            if (count >= 100) begin
                $display("... (Trace continues, truncated at 100 lines) ...");
                break;
            end
        end

        $display("------------------------------------------------------------------------------------------------------------------");
        $display("Read %0d records.", count);
        $fclose(fd);
        $finish;
    end

endmodule

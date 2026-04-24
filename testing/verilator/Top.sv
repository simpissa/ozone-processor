module Top (
    input clk,
    input reset,

    // Simple Memory Interface
    output reg [63:0] mem_addr,
    input      [31:0] mem_rdata,
    output reg        mem_en,

    // Status
    output reg        done,

    // Register File (Exposed for testbench to copy to SHM)
    output reg [63:0] x_regs [0:30]
);

    reg [31:0] state;
    reg [63:0] pc;

    always @(posedge clk) begin
        if (reset) begin
            state <= 0;
            done <= 0;
            pc <= 64'h20000000; // Default reset vector
            mem_en <= 0;
            for (int i=0; i<31; i++) x_regs[i] <= 0;
        end else if (!done) begin
            case (state)
                0: begin // Fetch
                    mem_addr <= pc;
                    mem_en <= 1;
                    state <= 1;
                end
                1: begin // Wait for memory
                    state <= 2;
                end
                2: begin // "Execute" (Dummy: just dump and stop)
                    $display("[RTL] Executing at PC 0x%h: Instruction 0x%h", pc, mem_rdata);

                    // Dummy side effects to prove SHM works
                    x_regs[0] <= 64'hCAFEBABE;
                    x_regs[1] <= {32'h0, mem_rdata}; // Copy instruction to X1

                    // If we see 0 (likely end of program or unmapped), stop
                    if (mem_rdata == 0 || pc > 64'h20000100) begin
                        done <= 1;
                    end else begin
                        pc <= pc + 4;
                        state <= 0;
                    end
                end
            endcase
        end
    end

endmodule

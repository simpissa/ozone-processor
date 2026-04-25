`timescale 1ns / 1ps
import types::*;
module lu_tb #(
    parameter int RS_ENTRIES = 4,
    parameter int TAG_LEN = 6,
    parameter int ID_LEN = 4
) ();
    logic        clk;
    logic        rst;
    logic        flush;

    logic         valid_in; // Set
    logic         ready_out;
    issue_payload_t in; // Set

    logic         valid_out;
    logic         ready_in;
    logic [63:0] addr;
    logic [63:0] imm;
    fu_op_t op;

    fu_result_t bus_in;     // Set


    logic [ID_LEN-1:0] memop_id;
    logic [63:0] final_addr;
    logic [ID_LEN-1:0] out;// Output
    logic tmp;
    logic tmp2;

    agu_rs #(.RS_ENTRIES(RS_ENTRIES),.TAG_LEN(TAG_LEN),.ID_LEN(ID_LEN)) rs (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .in(in),
        .bus(bus_in),
        .valid_out(valid_out),
        .ready_in(ready_in),
        .addr(addr),
        .imm(imm),
        .memop_id(memop_id)
    );

    agu # (.DELAY(1), .ID_LEN(ID_LEN)) agu_unit (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(valid_out),
        .ready_out(ready_in),
        .base_addr(addr),
        .imm(imm),
        .id(memop_id),
        .memop_id(out),
        .final_addr(final_addr),
        .valid_out(tmp),
        .ready_in(tmp2)
    );

    reg [314:0] trace_line; // Every test vectors is exactly this long
    integer fd;  // file descriptor

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
        //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    end

    //initial block...this is our test simulation
    initial begin
        fd = $fopen("output.txt", "r");  // STUDENTS: Edit me to edit your test vector
        // Set initial values
        rst = 0;
        @(posedge clk);
        rst = 1;
        @(posedge clk);
        rst = 0;

        while (!$feof(
            fd
        )) begin : test_loop
            // Get next line
            $fscanf(fd, "%b\n", trace_line);
            @(negedge clk)
            {valid_in,in,bus_in}=trace_line;
            $display(
                "valid: %b val: %h, mem_id: %b",tmp,final_addr,out
            );
        end : test_loop
        $fclose(fd);
        $finish;
    end

endmodule : lu_tb
`default_nettype wire
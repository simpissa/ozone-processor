`timescale 1ns / 1ps
import types::*;
module shifter_tb #(
    parameter int RS_ENTRIES = 4,
    parameter int TAG_LEN = 6
) ();
    logic        clk;
    logic        rst;
    logic        flush;

    logic         valid_in; // Set
    logic         ready_out;
    issue_payload_t in; // Set

    logic         valid_out;
    logic         ready_in;
    logic [63:0] arg1;
    logic [63:0] arg2;
    logic [TAG_LEN-1:0] dst_tag;
    logic should_output;
    fu_op_t op;

    fu_result_t bus_in;     // Set

    fu_result_t bus_out;    // Take output

    shifter_rs #(.RS_ENTRIES(RS_ENTRIES),.TAG_LEN(TAG_LEN)) rs (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .in(in),
        .bus(bus_in),
        .valid_out(valid_out),
        .ready_in(ready_in),
        .arg1(arg1),
        .arg2(arg2),
        .dst_tag(dst_tag),
        .should_output(should_output),
        .op(op)
    );

    shifter # (.DELAY(1), .TAG_LEN(6)) shifter_unit (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .valid_in(valid_out),
        .ready_out(ready_in),
        .arg1(arg1),
        .arg2(arg2),
        .tag(dst_tag),
        .should_output(should_output),
        .opcode(op),
        .bus_in(bus_in),
        .bus_out(bus_out)
    );

    reg [310:0] trace_line; // Every test vectors is exactly this long
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
                "valid: %b tag: %h val: %h flags: %b flags_valid: %b",bus_out.valid,bus_out.tag,bus_out.value,bus_out.flags,bus_out.flags_valid
            );
        end : test_loop
        $fclose(fd);
        $finish;
    end

endmodule : shifter_tb
`default_nettype wire
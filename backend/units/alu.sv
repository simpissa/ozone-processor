`timescale 1ns / 1ps

import types::*;

module alu #(
    parameter int unsigned DELAY = 1,
	parameter int unsigned tagW = 6
) (
	input logic clk,
	input logic rstN,
	input logic flush,

	// input
	input logic valid_in,
	output logic ready_out,
    input logic [63:0] arg1,
    input logic [63:0] arg2,
    input logic [TAG_LEN-1:0] tag,
    input logic [TAG_LEN-1:0] flag_tag,
    input logic should_output,
    input logic set_flags,
    input fu_op_t op,

    output logic valid_out,
    input logic ready_in,
    output fu_result_t result
);


initial begin 
    valid_out = 1'b0;
    ready_out = 1'b1;
    result = 0;
    count = 0;
end

// Keep the state over, cahnge the names or store in a struct
logic working_valid;
logic [63:0] working_arg1;
logic [63:0] working_arg2;
logic [TAG_LEN-1:0] working_tag;
logic [TAG_LEN-1:0] working_flag_tag;
logic working_should_output;
logic working_set_flags;
fu_op_t working_op;
// Assign result in comb, only validate in ff

always_comb begin
    result.valid = working_valid && ready_out && count >= DELAY;
    result.tag = working_tag;
    result.value = working_arg1 + working_arg2;
    // result.flags = TODO: Flag logic
    result.flags_valid = working_set_flags;
    //result.exception = ; TODO Exception logic
    // result.exception_code = ;
end

logic[$clog2(DELAY):0] count;
always_ff @(posedge clk) begin
    if(~rstN || flush) begin
        ready_out <= 1'b1;
    end else begin
        // If valid conditions reached set valid_out to true
        // Take in a value to compute, block the alu
        if(valid_in && ready_out) begin
            ready_out <= 1'b0;
            working_valid <= 1'b1;
            working_arg1 <= arg1;
            working_arg2 <= arg2;
            working_tag <= tag;
            working_flag_tag <= flag_tag;
            working_should_output <= should_output;
            working_set_flags <= set_flags;
            working_op <= op;
            count <= 1'b1;
        end else if(count >= DELAY && ready_in == 1'b1) begin
            ready_out <= 1'b1;
        end else begin
            count <= count + 1;
        end

        // Output values to rob and invalidate the results
        if(valid_out && ready_in) begin

        end
    end
end

endmodule

module alu_rs #(
    parameter int unsigned RS_ENTRIES = 4,
	parameter int unsigned tagW = 6
) (
	input logic clk,
	input logic rstN,
	input logic flush,

	// Issue input
	input logic issueValid,
	output logic issueReady,
    input issue_payload_t payload_bus,
    input fu_result_t cdb_out

    // Out to execute
    output logic        valid_out,
    input  logic         ready_in,
    output logic [63:0] arg1,
    output logic [63:0] arg2,
    output logic [TAG_LEN-1:0] tag,
    output logic [TAG_LEN-1:0] flag_tag,
    output logic should_output,
    output logic set_flags,
    output fu_op_t op
);

typedef struct packed {
    logic valid;
    logic waiting1;
    logic waiting2;
    logic [63:0] arg1;
    logic [63:0] arg2;
    logic [TAG_LEN-1:0] reg1_tag;
    logic [TAG_LEN-1:0] reg2_tag;
    logic [TAG_LEN-1:0] result_tag;
    logic [TAG_LEN-1:0] flag_tag;
    logic should_output;
    logic set_flags;
    fu_op_t op;
} rs_entry;

rs_entry[RS_ENTRIES-1:0] entries;
logic[$clog2(RS_ENTRIES):0] count;
logic[$clog2(RS_ENTRIES)-1:0] selected;

// On start up set payload to not valid
initial begin 
    count = 0;
    issueReady = 1;
    valid_out = 0;
    selected = 0;
end

logic[$clog2(RS_ENTRIES)-1:0] index_open;
logic open_valid;
logic[$clog2(RS_ENTRIES)-1:0] index_ready;
logic ready_valid;
logic[$clog2(RS_ENTRIES)-1:0] index_reg1_update;
logic reg1_update_valid;
logic[$clog2(RS_ENTRIES)-1:0] index_reg2_update;
logic reg2_update_valid;

always_comb begin
    index_open = 0;
    open_valid = 1'b0;
    index_ready = 0;
    ready_valid = 1'b0
    reg1_update_valid = 1'b0;
    index_reg1_update = 0;
    reg2_update_valid = 1'b0
    index_reg2_update = 0;

    for(int i = 0; i < RS_ENTRIES; i++) begin:
        if(~entries[i].valid) begin
            open_valid = 1'b1;
            index_open = i; // TODO cast to right bits
        end else begin
            if(~entries[i].waiting1 && ~entries[i].waiting2) begin
                ready_valid = 1'b1;
                index_ready = i;
            end

            // TODO does it matter if they are waiting
            if(cbd_out.valid) begin
                if(cbd_out.tag == entries[i].reg1_tag) begin
                    reg1_update_valid <= 1'b1;
                    index_reg1_update <= i;
                end else if(cbd_out.tag == entries[i].reg2_tag) begin
                    reg2_update_valid <= 1'b1;
                    index_reg2_update <= i;
                end
            end
        end
    end
end

logic will_insert = issueValid && issueReady;
logic will_remove = valid_out && ready_in;

always_ff @(posedge clk) begin
    // Output ready if done, disable ready if waiting on instr
    // At the same time output result/requests for rob
    if(~rstN || flush) begin
        issueReady <= 1'b1;
    end else begin
        // Insert issue into new rs
        // TODO ISSUE READY SHOULD BE SET IF THE COUNT IS CORRECT
        if(issueValid && issueReady && open_valid) begin
            count <= count + 1;
            entries[index_open].valid <= 1'b1;
            entries[index_open].waiting1 <= ~payload_bus.src1_ready;
            entries[index_open].waiting2 <= ~payload_bus.src2_ready && payload_bus.src2_valid;
            entries[index_open].arg1 <= payload_bus.src1_value;
            entries[index_open].arg2 <= payload_bus.src2_valid ? payload_bus.src2_value : payload_bus.imm;
            entries[index_open].reg1_tag <= payload_bus.src1_tag;
            entries[index_open].reg2_tag <= payload_bus.src2_tag;
            entries[index_open].result_tag <= payload_bus.dest_tag;
            entries[index_open].set_flags <= cond;
            entries[index_open].op <= fu_op; 
            // Add 1 to count
        end

        issueReady <= count <= RS_ENTRIES ? 1'b1 : 1'b0;

        // Valid out should be based on if current output is good

        // ALU accepted input, remove rs
        if(valid_out && ready_in) begin
            entries[selected].valid <= 1'b0;
            // I think this should be overwritten if its still
            // valid next cycle
            valid_out <= 1'b0;
            // Remove 1 from count
        end

        // Update rs' with cdb values
        for(int i = 0; i < RS_ENTRIES; i++) begin
            if(cdb_out.valid) begin
                if(cdb_out.tag == entries[i].reg1_tag) begin
                    entries[i].arg1 <= cdb.value;
                    entries[i].waiting1 <= 1'b0;
                end else if(cbd_out.tag == entries[i].reg2_tag) begin
                    entries[i].arg2 <= cdb.value;
                    entries[i].waiting2 <= 1'b0;
                end
            end 
        end

        // Output selected values
        if(ready_valid) begin
            // Might be able to move this to be 
            // always comb using selected?
            selected <= index_ready;
            valid_out <= 1'b1;
            arg1 <= entries[index_ready].arg1;
            arg2 <= entries[index_ready].arg2;
            tag <= entries[index_ready].result_tag;
            should_output <= 1'b1; // I think always for add?
            set_flags <= entries[index_ready].set_flags;
            op <= entries[index_ready].op;
        end
    end
end
endmodule
`timescale 1ns / 1ps

import types::*;

module agu #(
    parameter int DELAY = 1, // Should be >=1, number of cycles calculation of AGU takes
    parameter int TAG_LEN=6
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions

    // reservation station i/o
    input  logic        valid_in,
    output logic        ready_out,
    input  logic [63:0] base_addr,
    input  logic [63:0] imm,
    input  logic [TAG_LEN-1:0] dst_tag,

    // interact with bus
    input  fu_result_t bus_in,
    output fu_result_t bus_out
);
    logic [$clog2(DELAY):0] counter;
    logic pending;

    logic [TAG_LEN-1:0] result_tag; // Instr tag
    logic [63:0] result;    // Result of instr

    logic valid_out;
    assign valid_out = counter==($clog2(DELAY)+1)'(DELAY-1)&&pending;

    logic ready_in;
    assign ready_in = bus_in.valid && bus_in.tag==result_tag;

    // If no calculation pending or if output being extracted, can accept input
    assign ready_out=!pending||valid_out&&ready_in;

    assign bus_out.valid=valid_out;
    assign bus_out.tag=result_tag;
    assign bus_out.value=result;
    assign bus_out.flags=4'b0;
    assign bus_out.flags_valid=1'b0;
    assign bus_out.exception=1'b0;
    assign bus_out.exception_code=4'b0;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            counter <= 0;
            pending<=1'b0;
        end else begin
            if (valid_in&&ready_out) begin
                // Take in input
                counter<=0;
                pending<=1'b1;
                result<=imm+base_addr;
                result_tag<=dst_tag;
            end else if (valid_out&&ready_in) begin
                // If output and no input, pending variables no longer valid
                pending<=1'b0;
            end else if (!valid_out) begin
                counter<=counter+1;
            end
        end
    end
endmodule



module agu_rs #(
    parameter int RS_ENTRIES = 4,
    parameter int TAG_LEN = 6
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions (if in the middle of outputting multiple uops)

    // input from instruction issuer
    input  logic         valid_in,
    output logic         ready_out,
    input issue_payload_t in,

    // listen from bus
    input  fu_result_t bus,

    // output to AGU
    output logic        valid_out,
    input  logic         ready_in,
    output logic [63:0] addr,
    output logic [63:0] imm,
    output logic [TAG_LEN-1:0] dst_tag
);
    typedef struct packed {
        logic waiting;
        logic [63:0] addr;
        logic [63:0] imm;
        logic [TAG_LEN-1:0] wait_tag;  // tag to waiting on
        logic [TAG_LEN-1:0] dst_tag;  // tag to write to
    } rs_entry;

    rs_entry rs [RS_ENTRIES];
    logic [RS_ENTRIES-1:0] curr_entries;    // valid bits corresponding to rs entries
    logic [RS_ENTRIES-1:0] ready_entries;    // entries ready to be sent to agu
    
    // Comparing bus tag to entries
    logic [RS_ENTRIES-1:0] tag_matching;
    genvar i;
    generate
        for(i=0;i<RS_ENTRIES;i++) begin: tag_match
            assign ready_entries[i]=curr_entries[i]&&!rs[i].waiting;
            assign tag_matching[i]=curr_entries[i]&&rs[i].waiting&&bus.valid&&bus.tag==rs[i].wait_tag;
        end
    endgenerate

    assign ready_out = curr_entries!={RS_ENTRIES{1'b1}};

    logic [$clog2(RS_ENTRIES)-1:0] sent_index;  // Index of last entry sent to agu

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            curr_entries<=0;
        end else begin
            logic agu_accepted;
            logic selected;
            agu_accepted=valid_out&&ready_in;
            // Get entry from issuer
            if (valid_in && ready_out) begin
                logic inserted;
                inserted=1'b0;
                for (int j=0;j<RS_ENTRIES;j++) begin
                    if (!inserted&&!curr_entries[j]) begin
                        inserted=1'b1;
                        curr_entries[j]<=1'b1;
                        rs[j].waiting<=!in.src1_ready;
                        rs[j].addr<=in.src1_value;
                        rs[j].imm<=in.imm;
                        rs[j].wait_tag<=in.src1_tag;
                        rs[j].dst_tag<=in.dest_tag;
                    end
                end
            end
            // Accepted input, need to remove the entry from table
            if (agu_accepted) begin
                curr_entries[sent_index]<=1'b0;
            end

            // Choose entry to send to AGU
            selected=1'b0;
            for(int j=0;j<RS_ENTRIES;j++) begin
                if(!selected&&ready_entries[j]&&(!agu_accepted||j[$clog2(RS_ENTRIES)-1:0]!=sent_index)) begin
                    selected=1'b1;
                    sent_index<=j[$clog2(RS_ENTRIES)-1:0];
                    addr<=rs[j].addr;
                    imm<=rs[j].imm;
                    dst_tag<=rs[j].dst_tag;
                end
            end
            valid_out<=selected;

            // Update any entries matching with bus tag
            for (int j=0;j<RS_ENTRIES;j++) begin
                if(tag_matching[j]) begin
                    rs[j].waiting<=1'b0;
                    rs[j].addr<=bus.value;
                end
            end
        end
    end
endmodule
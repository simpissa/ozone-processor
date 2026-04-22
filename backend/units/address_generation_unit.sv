`timescale 1ns / 1ps

import types::*;

module agu #(
    parameter int DELAY = 1, // Should be >=1, number of cycles calculation of AGU takes
    parameter int ID_LEN = 4
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions

    // reservation station i/o
    input  logic        valid_in,
    output logic        ready_out,
    input  logic [63:0] base_addr,
    input  logic [63:0] imm,
    input  logic [ID_LEN-1:0] id,

    // output to mem unit i/o
    output logic         valid_out,
    input  logic         ready_in,
    output logic [63:0] final_addr, // Resulting addr
    output logic [ID_LEN-1:0] memop_id
);
    logic [$clog2(DELAY)-1:0] counter;
    logic pending;

    // If no addr calculation pending or if output being extracted, can accept input
    assign ready_out=!pending||valid_out&&ready_in;
    assign valid_out = counter==(DELAY-1)&&pending;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            counter <= 0;
            pending<=1'b0;
        end else begin
            if (valid_in&&ready_out) begin
                // Take in input
                counter<=0;
                pending<=1'b1;
                final_addr<=imm+base_addr;
                memop_id<=id;
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
    parameter int TAG_LEN = 6,
    parameter int ID_LEN = 4
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions (if in the middle of outputting multiple uops)

    // input from instruction issuer
    input  logic         valid_in,
    output logic         ready_out,
    input logic input_resolved,     // 1 indicates that input_reg_val contains valid value, else need to wait for bus
    input logic [63:0] input_imm,
    input logic [63:0] input_reg_val,
    input logic [TAG_LEN-1:0] input_tag,
    input logic [ID_LEN-1:0] lsq_id,    // corresponds to id of memory op trace

    // listen from bus
    input  fu_result_t bus,

    // output to AGU
    output logic        valid_out,
    input  logic         ready_in,
    output logic [63:0] addr,
    output logic [63:0] imm,
    output logic [ID_LEN-1:0] memop_id
);
    typedef struct packed {
        logic waiting;
        logic [63:0] addr;
        logic [63:0] imm;
        logic [TAG_LEN-1:0] tag;  // tag to waiting on
        logic [ID_LEN-1:0] id;    // mem op id (pass to agu to pass to mem unit)
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
            assign tag_matching[i]=curr_entries[i]&&rs[i].waiting&&bus.valid&&bus.tag==rs[i].tag;
        end
    endgenerate

    assign ready_out = curr_entries!={RS_ENTRIES{1'b1}};

    logic [$clog2(RS_ENTRIES)-1:0] sent_index;  // Index of last entry sent to agu

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            curr_entries<=0;
        end else begin
            // Get entry from issuer
            if (valid_in && ready_out) begin
                logic inserted;
                inserted=1'b0;
                for (int j=0;j<RS_ENTRIES;j++) begin
                    if (!inserted&&!curr_entries[j]) begin
                        inserted=1'b1;
                        curr_entries[j]<=1'b1;
                        rs[j].waiting<=!input_resolved;
                        rs[j].addr<=input_reg_val;
                        rs[j].imm<=input_imm;
                        rs[j].tag<=input_tag;
                        rs[j].id<=lsq_id;
                    end
                end
            end
            logic agu_accepted;
            agu_accepted=valid_out&&ready_in;
            // Accepted input, need to remove the entry from table
            if (agu_accepted) begin
                curr_entries[sent_index]<=1'b0;
            end

            // Choose entry to send to AGU
            logic selected;
            selected=1'b0;
            for(int j=0;j<RS_ENTRIES;j++) begin
                if(!selected&&ready_entries[j]&&(!agu_accepted||j!=sent_index)) begin
                    selected=1'b1;
                    sent_index<=j;
                    addr<=rs[j].addr;
                    imm<=rs[j].imm;
                    memop_id<=rs[j].id;
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
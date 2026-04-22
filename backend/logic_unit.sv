`timescale 1ns / 1ps

import types::*;

module lu #(
    parameter int DELAY = 1, // Should be >=1, number of cycles calculation of LU takes
    parameter int TAG_LEN = 6
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions

    // reservation station i/o
    input logic       valid_in,
    output logic      ready_out,
    input logic [63:0] arg1,
    input logic [63:0] arg2,
    input logic [TAG_LEN-1:0] tag,
    input logic [TAG_LEN-1:0] flag_tag, // TODO: how are we handling flags? As separate reg? Do flags have separate bus? Add to CDB width?
    input logic should_output,
    input logic set_flags,
    input fu_op_t opcode,

    // listen to bus to see if value accepted
    input fu_result_t bus_in,

    // output to bus
    output fu_result_t bus_out
);
    logic [$clog2(DELAY)-1:0] counter;
    logic pending;

    logic [TAG_LEN-1:0] result_tag; // Instr tag
    logic [63:0] result;    // Result of instr
    logic send_to_bus;      // If instr should send to bus
    logic [3:0] flag_results;   // New flags resulting from operation TODO: how to give?
    
    logic valid_out;
    assign valid_out = counter==(DELAY-1)&&pending;

    logic ready_in;
    assign ready_in = !send_to_bus||bus_in.valid && bus_in.tag==result_tag;

    // If no calculation pending or if output being extracted, can accept input
    assign ready_out=!pending||valid_out&&ready_in;

    // TODO: may have to change to valid_out&&!ready_in if bus takes 1 cycle instead of combinational
    // I think this is correct though
    assign bus_out={valid_out&&send_to_bus,result_tag,result,70{1'b0}};

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            counter <= 0;
            pending<=1'b0;
            result_tag<= 0;
            result<=0;
            send_to_bus<=0;
            flag_results<=0;
        end else begin
            if (valid_in&&ready_out) begin
                // Take in input
                counter<=0;
                pending<=1'b1;
                result_tag<=tag;
                case (opcode)
                    // TODO Set flags if (set_flags)
                    OP_XOR: begin
                        result<=arg1^arg2;
                    end
                    OP_AND: begin
                        result<=arg1&arg2;
                    end
                    OP_OR: begin
                        result<=arg1|arg2;
                    end
                    OP_NOT: begin
                        result<=!arg1;
                    end
                endcase
                send_to_bus<=should_output;
            end else if (valid_out&&ready_in) begin
                // If output and no input, pending variables no longer valid
                pending<=1'b0;
            end else if (!valid_out) begin
                counter<=counter+1;
            end
        end
    end
endmodule



module lu_rs #(
    parameter int RS_ENTRIES = 4,
    parameter int TAG_LEN = 6
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush, // flush on branch mispredictions (if in the middle of outputting multiple uops)

    // input from instruction issuer
    input  logic         valid_in,
    output logic         ready_out,
    input logic input1_resolved,
    input logic input2_resolved,
    input logic [63:0] input1_val,
    input logic [63:0] input2_val,
    input logic [TAG_LEN-1:0] input1_tag,
    input logic [TAG_LEN-1:0] input2_tag,
    input logic [TAG_LEN-1:0] result_tag,
    input logic [TAG_LEN-1:0] input_flag_tag, // TODO: handling flags?
    input logic input_should_output,      // set to false if shouldn't output result to bus (such as writing to XZR)
    input logic input_set_flags,
    input fu_op_t opcode,

    // listen from bus
    input  fu_result_t bus,

    // output to logical unit
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

    rs_entry rs [RS_ENTRIES];
    logic [RS_ENTRIES-1:0] curr_entries;    // valid bits corresponding to rs entries
    logic [RS_ENTRIES-1:0] ready_entries;    // entries ready to be sent to lu
    
    // Comparing bus tag to entries
    logic [RS_ENTRIES-1:0] tag1_matching;
    logic [RS_ENTRIES-1:0] tag2_matching;
    genvar i;
    generate
        for(i=0;i<RS_ENTRIES;i++) begin: tag_match
            assign ready_entries[i]=curr_entries[i]&&!rs[i].waiting1&&!rs[i].waiting2;
            assign tag1_matching[i]=curr_entries[i]&&rs[i].waiting1&&bus.valid&&bus.tag==rs[i].reg1_tag;
            assign tag2_matching[i]=curr_entries[i]&&rs[i].waiting2&&bus.valid&&bus.tag==rs[i].reg2_tag;
        end
    endgenerate

    assign ready_out = curr_entries!={RS_ENTRIES{1'b1}};

    logic [$clog2(RS_ENTRIES)-1:0] sent_index;  // Index of last entry sent to lu

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
                        rs[j].waiting1<=!input1_resolved;
                        rs[j].waiting2<=!input2_resolved;
                        rs[j].arg1<=input1_val;
                        rs[j].arg2<=input2_val;
                        rs[j].reg1_tag<=input1_tag;
                        rs[j].reg2_tag<=input2_tag;
                        rs[j].result_tag<=result_tag;
                        rs[j].flag_tag<=input_flag_tag;
                        rs[j].should_output<=input_should_output;
                        rs[j].set_flags<=input_set_flags;
                        rs[j].op<=opcode;
                    end
                end
            end
            logic lu_accepted;
            lu_accepted=valid_out&&ready_in;
            // Accepted input, need to remove the entry from table
            if (lu_accepted) begin
                curr_entries[sent_index]<=1'b0;
            end

            // Choose entry to send to LU
            logic selected;
            selected=1'b0;
            for(int j=0;j<RS_ENTRIES;j++) begin
                if(!selected&&ready_entries[j]&&(!lu_accepted||j!=sent_index)) begin
                    selected=1'b1;
                    sent_index<=j;
                    arg1<=rs[j].arg1;
                    arg2<=rs[j].arg2;
                    tag<=rs[j].result_tag;
                    flag_tag<=rs[j].flag_tag;
                    should_output<=rs[j].should_output;
                    set_flags<=rs[j].set_flags;
                    op<=rs[j].op;
                end
            end
            valid_out<=selected;

            // Update any entries matching with bus tag
            for (int j=0;j<RS_ENTRIES;j++){
                if(tag1_matching[j]) begin
                    rs[j].waiting1<=1'b0;
                    rs[j].arg1<=bus.value;
                end
                if(tag2_matching[j]) begin
                    rs[j].waiting2<=1'b0;
                    rs[j].arg2<=bus.value;
                end
            }
        end
    end
endmodule
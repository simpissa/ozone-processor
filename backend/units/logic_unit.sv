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
    input logic should_output,
    input logic set_flags,
    input fu_op_t opcode,

    // listen to bus to see if value accepted
    input fu_result_t bus_in,

    // output to bus
    output fu_result_t bus_out
);
    logic [$clog2(DELAY):0] counter;
    logic pending;

    logic [TAG_LEN-1:0] result_tag; // Instr tag
    logic [63:0] result;    // Result of instr
    logic send_to_bus;      // If instr should send to bus
    logic [3:0] flag_results;   // New flags resulting from operation
    logic flags_valid;
    
    logic valid_out;
    assign valid_out = counter==($clog2(DELAY)+1)'(DELAY-1)&&pending;

    logic ready_in;
    assign ready_in = !send_to_bus||bus_in.valid && bus_in.tag==result_tag;

    // If no calculation pending or if output being extracted, can accept input
    assign ready_out=!pending||valid_out&&ready_in;

    assign bus_out.valid=valid_out&&send_to_bus;
    assign bus_out.tag=result_tag;
    assign bus_out.value=result;
    assign bus_out.flags=flag_results;
    assign bus_out.flags_valid=flags_valid;
    assign bus_out.exception=1'b0;
    assign bus_out.exception_code=4'b0;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            counter <= '0;
            pending<='0;
            result_tag<= '0;
            result<='0;
            send_to_bus<='0;
            flag_results<='0;
            flags_valid<='0;
        end else begin
            if (valid_in&&ready_out) begin
                logic [63:0] temp_result;
                // Take in input
                counter<=0;
                pending<=1'b1;
                result_tag<=tag;
                case (opcode)
                    OP_XOR: begin
                        temp_result=arg1^arg2;
                    end
                    OP_AND: begin
                        temp_result=arg1&arg2;
                    end
                    OP_OR: begin
                        temp_result=arg1|arg2;
                    end
                    OP_NOT: begin
                        temp_result=~arg1;
                    end
                    OP_MOV: begin
                        temp_result=arg1;
                    end
                    default: temp_result=arg1;
                endcase
                result<=temp_result;
                if(set_flags) begin
                    flag_results<={temp_result[63],temp_result=='0,1'b0,1'b0};
                end
                send_to_bus<=should_output;
                flags_valid<=set_flags;
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
    input issue_payload_t in,

    // listen from bus
    input  fu_result_t bus,

    // output to logical unit
    output logic         valid_out,
    input  logic         ready_in,
    output logic [63:0] arg1,
    output logic [63:0] arg2,
    output logic [TAG_LEN-1:0] dst_tag,
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
            logic lu_accepted;
            logic selected;
            lu_accepted=valid_out&&ready_in;
            // Get entry from issuer
            if (valid_in && ready_out) begin
                logic inserted;
                inserted=1'b0;
                for (int j=0;j<RS_ENTRIES;j++) begin
                    if (!inserted&&!curr_entries[j]) begin
                        inserted=1'b1;
                        curr_entries[j]<=1'b1;
                        rs[j].waiting1<=in.src1_valid && !in.src1_ready;
                        rs[j].waiting2<=in.src2_valid && !in.src2_ready;
                        rs[j].arg1<=in.src1_value;
                        rs[j].arg2<=in.src2_valid ? in.src2_value : (in.imm_valid ? in.imm : 64'd0);
                        rs[j].reg1_tag<=in.src1_tag;
                        rs[j].reg2_tag<=in.src2_tag;
                        rs[j].result_tag<=in.dest_tag;
                        rs[j].should_output<=in.dest_valid;
                        rs[j].set_flags<=in.set_flags;
                        rs[j].op<=in.fu_op;
                    end
                end
            end
            
            
            // Accepted input, need to remove the entry from table
            if (lu_accepted) begin
                curr_entries[sent_index]<=1'b0;
            end

            // Choose entry to send to LU
            selected=1'b0;
            for(int j=0;j<RS_ENTRIES;j++) begin
                if(!selected&&ready_entries[j]&&(!lu_accepted||j[$clog2(RS_ENTRIES)-1:0]!=sent_index)) begin
                    selected=1'b1;
                    sent_index<=j[$clog2(RS_ENTRIES)-1:0];
                    arg1<=rs[j].arg1;
                    arg2<=rs[j].arg2;
                    dst_tag<=rs[j].result_tag;
                    should_output<=rs[j].should_output;
                    set_flags<=rs[j].set_flags;
                    op<=rs[j].op;
                end
            end
            valid_out<=selected;

            // Update any entries matching with bus tag
            for (int j=0;j<RS_ENTRIES;j++) begin
                if(tag1_matching[j]) begin
                    rs[j].waiting1<=1'b0;
                    rs[j].arg1<=bus.value;
                end
                if(tag2_matching[j]) begin
                    rs[j].waiting2<=1'b0;
                    rs[j].arg2<=bus.value;
                end
            end
        end
    end
endmodule

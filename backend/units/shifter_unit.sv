`timescale 1ns / 1ps

import types::*;

// Barrel shifter implementation
module barrelshifter #(parameter D_SIZE=64) (
  input  logic [D_SIZE-1:0]         x_in,
  input  logic [$clog2(D_SIZE)-1:0] s_in,
  input  logic [2:0]                op_in,
  output logic [D_SIZE-1:0]         y_out,
  output logic                      zf_out,
  output logic                      vf_out
);
  logic not_msb;
  not (not_msb, x_in[D_SIZE-1]);
  logic [$clog2(D_SIZE):0] overflow;
  assign overflow[0]=1'b1;
  logic [D_SIZE-1:0] results[$clog2(D_SIZE)+1];
  logic [D_SIZE-1:0] rev;
  reverse #(D_SIZE) r1 (.a(x_in),.ans(rev));
  mux2 #(D_SIZE) m1 (.s(op_in[2]),.a(rev),.b(x_in),.ans(results[0][D_SIZE-1:0]));
  logic rightshift;
  not (rightshift, op_in[2]);
  genvar i;
  generate
    for(i=0;i<$clog2(D_SIZE);i++) begin: forloop
      logic [D_SIZE-1:0] buff;
      logic [D_SIZE-1:0] over;
      logic misc;
      and (misc, rightshift, op_in[0],results[0][0]);
      assign {over,buff} = {{D_SIZE-(1<<i){1'b0}},results[i][D_SIZE-1:0],{(1<<i){misc}}};
      logic [D_SIZE-1:0] buf2;
      assign buf2[D_SIZE-1:(1<<i)]=buff[D_SIZE-1:(1<<i)];
      mux2 #(1<<i) m2 (.s(op_in[1]),.a(buff[(1<<i)-1:0]),.b(over[(1<<i)-1:0]),.ans(buf2[(1<<i)-1:0]));
      mux2 #(D_SIZE) m3 (.s(s_in[i]),.a(results[i][D_SIZE-1:0]),.b(buf2),.ans(results[i+1][D_SIZE-1:0]));
      logic no_overflow;
      checkbits #((1<<i)+1) chk1 (.a(results[i][D_SIZE-1:D_SIZE-1-(1<<i)]),.b(not_msb),.ans(no_overflow));
      logic invalid_iteration;
      not (invalid_iteration, s_in[i]);
      logic no_overflow_iteration;
      or (no_overflow_iteration, no_overflow, invalid_iteration);
      and (overflow[i+1],overflow[i],no_overflow_iteration);
    end: forloop
  endgenerate
  
  logic [D_SIZE-1:0] rev2;
  reverse #(D_SIZE) r2 (.a(results[$clog2(D_SIZE)][D_SIZE-1:0]),.ans(rev2));

  logic [D_SIZE-1:0] pre_result;
  mux2 #(D_SIZE) m4 (.s(op_in[2]),.a(rev2),.b(results[$clog2(D_SIZE)][D_SIZE-1:0]),.ans(pre_result));
  assign y_out[D_SIZE-2:0] = pre_result[D_SIZE-2:0];
  logic temp;
  not (temp, op_in[1]);
  logic msb_change;
  not (msb_change, overflow[$clog2(D_SIZE)]);
  and (vf_out, op_in[2],temp,op_in[0],msb_change);
  mux2 #(1) m5 (.s(vf_out),.a(pre_result[D_SIZE-1]),.b(x_in[D_SIZE-1]),.ans(y_out[D_SIZE-1]));
  checkbits #(D_SIZE) chk2 (.a(y_out),.b(1'b1),.ans(zf_out));
endmodule: barrelshifter


module mux2 #(parameter D_SIZE=64) (
  input logic s,
  input logic [D_SIZE-1:0] a,
  input logic [D_SIZE-1:0] b,
  output logic [D_SIZE-1:0] ans
);
  genvar i;
  generate
    for(i=0;i<D_SIZE;i++) begin:forloop
      logic x,y,not_s;
      not (not_s,s);
      and (x,not_s,a[i]);
      and (y,s,b[i]);
      or (ans[i],x,y);
    end:forloop
  endgenerate
endmodule: mux2

module reverse #(parameter D_SIZE) (
  input logic [D_SIZE-1:0] a,
  output logic [D_SIZE-1:0] ans
);
  genvar i;
  generate
    for(i=0;i<D_SIZE;i++)  begin:forloop
      assign ans[i]=a[D_SIZE-1-i];
    end:forloop
  endgenerate
endmodule: reverse

module checkbits #(parameter D_SIZE) (
  input logic [D_SIZE-1:0] a,
  input logic b,
  output logic ans
);
  logic [D_SIZE-1:0] res;
  xor (res[0], a[0], b);
  genvar i;
  generate
    for(i=0;i+1<D_SIZE;i++)  begin:forloop
      logic chk;
      xor (chk, a[i+1], b);
      and (res[i+1], res[i], chk);
    end:forloop
  endgenerate
  assign ans = res[D_SIZE-1];
endmodule: checkbits



// Shifter unit
module shifter #(
    parameter int DELAY = 1, // Should be >=1, number of cycles calculation of shifter takes
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
    
    logic valid_out;
    assign valid_out = counter==(DELAY-1)&&pending;

    logic ready_in;
    assign ready_in = !send_to_bus||bus_in.valid && bus_in.tag==result_tag;

    // If no calculation pending or if output being extracted, can accept input
    assign ready_out=!pending||valid_out&&ready_in;

    assign bus_out.valid=valid_out&&send_to_bus;
    assign bus_out.tag=result_tag;
    assign bus_out.value=result;
    assign bus_out.flags=4'b0;
    assign bus_out.flags_valid=1'b0;
    assign bus_out.exception=1'b0;
    assign bus_out.exception_code=4'b0;

    // Wires to barrel shifter
    logic [63:0] bshift_x_in;
    logic [5:0] bshift_s_in;
    logic [2:0] bshift_op_in;
    logic bshift_zf_out;    // Unused
    logic bshift_vf_out;    // Unused
    barrelshifter #(64) bshifter (.x_in(bshift_x_in),.s_in(bshift_s_in),.op_in(bshift_op_in),.y_out(result),.zf_out(bshift_zf_out),vf_out(bshift_vf_out));

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            counter <= '0;
            pending<='0;
            result_tag<= '0;
            send_to_bus<='0;
            bshift_x_in<='0;
            bshift_s_in<='0;
            bshift_op_in<='0;
            bshift_y_out<='0;
            bshift_zf_out<='0;
            bshift_vf_out<='0;
        end else begin
            if (valid_in&&ready_out) begin
                // Take in input
                counter<=0;
                pending<=1'b1;
                result_tag<=tag;
                bshift_x_in<=arg1;
                bshift_s_in<=arg2[5:0]; // TODO: make sure this is correct (take modulo 64 of shift val)
                case (opcode)
                    OP_LSL: begin
                        bshift_op_in<=3'b100;
                    end
                    OP_LSR: begin
                        bshift_op_in<=3'b000;
                    end
                    OP_ASR: begin
                        bshift_op_in<=3'b001;
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



module shifter_rs #(
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
        fu_op_t op;
    } rs_entry;

    rs_entry rs [RS_ENTRIES];
    logic [RS_ENTRIES-1:0] curr_entries;    // valid bits corresponding to rs entries
    logic [RS_ENTRIES-1:0] ready_entries;    // entries ready to be sent to shifter
    
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

    logic [$clog2(RS_ENTRIES)-1:0] sent_index;  // Index of last entry sent to shifter

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
                        rs[j].waiting1<=!in.src1_ready;
                        rs[j].waiting2<=!in.src2_ready;
                        rs[j].arg1<=in.src1_value;
                        rs[j].arg2<=in.src2_value;
                        rs[j].reg1_tag<=in.src1_tag;
                        rs[j].reg2_tag<=in.src2_tag;
                        rs[j].result_tag<=in.dest_tag;
                        rs[j].should_output<=in.dest_valid;
                        rs[j].op<=opcode;
                    end
                end
            end
            logic shifter_accepted;
            shifter_accepted=valid_out&&ready_in;
            // Accepted input, need to remove the entry from table
            if (shifter_accepted) begin
                curr_entries[sent_index]<=1'b0;
            end

            // Choose entry to send to shifter
            logic selected;
            selected=1'b0;
            for(int j=0;j<RS_ENTRIES;j++) begin
                if(!selected&&ready_entries[j]&&(!shifter_accepted||j!=sent_index)) begin
                    selected=1'b1;
                    sent_index<=j;
                    arg1<=rs[j].arg1;
                    arg2<=rs[j].arg2;
                    dst_tag<=rs[j].result_tag;
                    should_output<=rs[j].should_output;
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
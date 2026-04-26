`timescale 1ns / 1ps

import types::*;

module alu #(
    parameter int unsigned DELAY = 1,
    parameter int unsigned TAG_LEN = 6
) (
    input  logic               clk,
    input  logic               rstN,
    input  logic               flush,
    input  logic               valid_in,
    output logic               ready_out,
    input  logic [63:0]        arg1,
    input  logic [63:0]        arg2,
    input  logic [TAG_LEN-1:0] tag,
    input  logic               should_output,
    input  logic               set_flags,
    input  logic               src2_valid,
    input  logic [3:0]         cond,
    input  logic [63:0]        imm,
    input  fu_op_t             op,
    input  fu_result_t         bus_in,
    output fu_result_t         bus_out
);

    logic [$clog2(DELAY+1):0] counter;
    logic pending;
    logic [TAG_LEN-1:0] result_tag;
    logic [63:0] result_value;
    logic [3:0] result_flags;
    logic result_flags_valid;
    logic send_to_bus;

    logic valid_out;
    logic accepted_by_bus;

    assign valid_out = pending && (counter >= DELAY[$bits(counter)-1:0]);
    assign accepted_by_bus = !send_to_bus || (bus_in.valid && (bus_in.tag == result_tag));
    assign ready_out = !pending || (valid_out && accepted_by_bus);

    assign bus_out.valid = valid_out && send_to_bus;
    assign bus_out.tag = result_tag;
    assign bus_out.value = result_value;
    assign bus_out.flags = result_flags;
    assign bus_out.flags_valid = result_flags_valid;
    assign bus_out.exception = 1'b0;
    assign bus_out.exception_code = EXC_CODE_NONE;

    function automatic logic cond_true(input logic [3:0] cnd, input logic [3:0] flags);
        logic n;
        logic z;
        logic c;
        logic v;
        begin
            n = flags[3];
            z = flags[2];
            c = flags[1];
            v = flags[0];
            unique case (cnd)
                4'h0: cond_true = z;
                4'h1: cond_true = !z;
                4'h2: cond_true = c;
                4'h3: cond_true = !c;
                4'h4: cond_true = n;
                4'h5: cond_true = !n;
                4'h6: cond_true = v;
                4'h7: cond_true = !v;
                4'h8: cond_true = c && !z;
                4'h9: cond_true = !c || z;
                4'ha: cond_true = (n == v);
                4'hb: cond_true = (n != v);
                4'hc: cond_true = !z && (n == v);
                4'hd: cond_true = z || (n != v);
                4'he: cond_true = 1'b1;
                default: cond_true = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [3:0] add_flags(input logic [63:0] a, input logic [63:0] b, input logic [63:0] y);
        logic [64:0] sum;
        begin
            sum = {1'b0, a} + {1'b0, b};
            add_flags = {y[63], (y == 64'd0), sum[64], ((a[63] == b[63]) && (y[63] != a[63]))};
        end
    endfunction

    function automatic logic [3:0] sub_flags(input logic [63:0] a, input logic [63:0] b, input logic [63:0] y);
        begin
            sub_flags = {y[63], (y == 64'd0), (a >= b), ((a[63] != b[63]) && (y[63] != a[63]))};
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rstN || flush) begin
            counter <= '0;
            pending <= 1'b0;
            result_tag <= '0;
            result_value <= 64'd0;
            result_flags <= 4'd0;
            result_flags_valid <= 1'b0;
            send_to_bus <= 1'b0;
        end else begin
            if (valid_in && ready_out) begin
                logic [63:0] temp_result;
                counter <= '0;
                pending <= 1'b1;
                result_tag <= tag;
                send_to_bus <= should_output;
                result_flags_valid <= set_flags;

                unique case (op)
                    OP_SUB: begin
                        temp_result = arg1 - arg2;
                        result_flags <= sub_flags(arg1, arg2, temp_result);
                    end
                    OP_COND_CHECK: begin
                        if (src2_valid) begin
                            temp_result = arg2[0] ? (arg1 + imm) : (arg1 + 64'd4);
                        end else begin
                            temp_result = {63'd0, cond_true(cond, arg1[3:0])};
                        end
                        result_flags <= 4'd0;
                    end
                    default: begin
                        temp_result = arg1 + arg2;
                        result_flags <= add_flags(arg1, arg2, temp_result);
                    end
                endcase

                result_value <= temp_result;
            end else if (valid_out && accepted_by_bus) begin
                pending <= 1'b0;
            end else if (pending && !valid_out) begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule

module alu_rs #(
    parameter int unsigned RS_ENTRIES = 4,
    parameter int unsigned TAG_LEN = 6
) (
    input  logic           clk,
    input  logic           rstN,
    input  logic           flush,
    input  logic           issueValid,
    output logic           issueReady,
    input  issue_payload_t payload_bus,
    input  fu_result_t     cdb_out,
    output logic           valid_out,
    input  logic           ready_in,
    output logic [63:0]    arg1,
    output logic [63:0]    arg2,
    output logic [TAG_LEN-1:0] tag,
    output logic           should_output,
    output logic           set_flags,
    output logic           src2_valid,
    output logic [3:0]     cond,
    output logic [63:0]    imm,
    output fu_op_t         op
);

    typedef struct packed {
        logic valid;
        logic waiting1;
        logic waiting2;
        logic waiting1_flags;
        logic waiting2_flags;
        logic [63:0] arg1;
        logic [63:0] arg2;
        logic [TAG_LEN-1:0] reg1_tag;
        logic [TAG_LEN-1:0] reg2_tag;
        logic [TAG_LEN-1:0] result_tag;
        logic should_output;
        logic set_flags;
        logic src2_valid;
        logic [3:0] cond;
        logic [63:0] imm;
        fu_op_t op;
    } rs_entry_t;

    rs_entry_t entries [RS_ENTRIES];
    logic [RS_ENTRIES-1:0] curr_entries;
    logic [RS_ENTRIES-1:0] ready_entries;
    logic [$clog2(RS_ENTRIES)-1:0] sent_index;

    genvar i;
    generate
        for (i = 0; i < RS_ENTRIES; i++) begin: ready_gen
            assign ready_entries[i] = curr_entries[i] && !entries[i].waiting1 && !entries[i].waiting2;
        end
    endgenerate

    assign issueReady = curr_entries != {RS_ENTRIES{1'b1}};

    always_ff @(posedge clk) begin
        if (!rstN || flush) begin
            curr_entries <= '0;
            valid_out <= 1'b0;
            sent_index <= '0;
        end else begin
            logic accepted;
            logic selected;
            accepted = valid_out && ready_in;

            if (issueValid && issueReady) begin
                logic inserted;
                inserted = 1'b0;
                for (int j = 0; j < RS_ENTRIES; j++) begin
                    if (!inserted && !curr_entries[j]) begin
                        inserted = 1'b1;
                        curr_entries[j] <= 1'b1;
                        entries[j].waiting1 <= payload_bus.src1_valid && !payload_bus.src1_ready;
                        entries[j].waiting2 <= payload_bus.src2_valid && !payload_bus.src2_ready;
                        entries[j].waiting1_flags <= payload_bus.src1_is_flags;
                        entries[j].waiting2_flags <= payload_bus.src2_is_flags;
                        entries[j].arg1 <= payload_bus.src1_value;
                        entries[j].arg2 <= payload_bus.src2_valid ? payload_bus.src2_value :
                                           (payload_bus.imm_valid ? payload_bus.imm : 64'd0);
                        entries[j].reg1_tag <= payload_bus.src1_tag;
                        entries[j].reg2_tag <= payload_bus.src2_tag;
                        entries[j].result_tag <= payload_bus.dest_tag;
                        entries[j].should_output <= payload_bus.dest_valid || payload_bus.fu_op == OP_COND_CHECK;
                        entries[j].set_flags <= payload_bus.set_flags;
                        entries[j].src2_valid <= payload_bus.src2_valid;
                        entries[j].cond <= payload_bus.cond;
                        entries[j].imm <= payload_bus.imm;
                        entries[j].op <= payload_bus.fu_op;
                    end
                end
            end

            if (accepted) begin
                curr_entries[sent_index] <= 1'b0;
            end

            selected = 1'b0;
            for (int j = 0; j < RS_ENTRIES; j++) begin
                if (!selected && ready_entries[j] && (!accepted || j[$clog2(RS_ENTRIES)-1:0] != sent_index)) begin
                    selected = 1'b1;
                    sent_index <= j[$clog2(RS_ENTRIES)-1:0];
                    arg1 <= entries[j].arg1;
                    arg2 <= entries[j].arg2;
                    tag <= entries[j].result_tag;
                    should_output <= entries[j].should_output;
                    set_flags <= entries[j].set_flags;
                    src2_valid <= entries[j].src2_valid;
                    cond <= entries[j].cond;
                    imm <= entries[j].imm;
                    op <= entries[j].op;
                end
            end
            valid_out <= selected;

            if (cdb_out.valid) begin
                for (int j = 0; j < RS_ENTRIES; j++) begin
                    if (curr_entries[j] && entries[j].waiting1 && cdb_out.tag == entries[j].reg1_tag) begin
                        entries[j].waiting1 <= 1'b0;
                        entries[j].arg1 <= entries[j].waiting1_flags ? {{60{1'b0}}, cdb_out.flags} : cdb_out.value;
                    end
                    if (curr_entries[j] && entries[j].waiting2 && cdb_out.tag == entries[j].reg2_tag) begin
                        entries[j].waiting2 <= 1'b0;
                        entries[j].arg2 <= entries[j].waiting2_flags ? {{60{1'b0}}, cdb_out.flags} : cdb_out.value;
                    end
                end
            end
        end
    end

endmodule

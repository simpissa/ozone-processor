`timescale 1ns / 1ps

import types::*;

module store_queue #(
    parameter int SQ_SIZE = 8,
    parameter int ROB_TAG_W = 6
)(
    input logic rst,           // reset
    input logic flush,
    input logic clk_in,        // clock
    
    // Interacting with trace
    /*
    input logic valid_trace,         // input trace is valid
    output logic ready_out,           // ready to receive new input trace

    // Data
    input logic [3:0] trace_id,
    input logic [47:0] trace_vaddr,
    input logic trace_vaddr_is_valid,
    input logic trace_value_is_valid,
    input logic [63:0] trace_value,
    input logic resolve,
    input logic [ROB_TAG_W-1:0] age,      // Current age
    */

    // replaces traces, essentially
    input fu_result_t cdb_i,
    input logic payload_valid_i,
    input issue_payload_t payload_i,
    output logic payload_ready_o,


    // Interacting with read queue
    input logic [47:0] search_addr,
    input logic [ROB_TAG_W-1:0] load_age,      // Age of load

    output logic found, // 1 if address found, 0 if not found
    output logic resolved, // if found: 0 if unresolved, 1 if valid value
    output logic [63:0] search_value,


    // Get age of oldest instruction in LQ
    input logic [ROB_TAG_W-1:0] lq_head_age,
    input logic lq_head_valid,

    input logic commit_valid,
    input logic [ROB_TAG_W-1:0] commit_tag,


    // Note sure when can commit stores, should be given by ROB
    // Interacting with L1 cache
    output logic [47:0] write_vaddr,
    output logic [63:0] write_value,
    input logic ready_in,
    output logic valid_out
);
    function automatic int msb_runtime(input logic [SQ_SIZE-1:0] value);
        integer result;
        logic [SQ_SIZE-1:0] v;
        begin
            result = 0;
            v = value;
            for (int i = 0; i<SQ_SIZE;i++) begin
                if (v[0]) begin
                    result = i;
                end
                v = v>>1;
            end
            return result;
        end
    endfunction

    typedef struct packed {
        //logic [3:0] trace_id;
        logic [ROB_TAG_W-1:0] trace_id;
        logic [47:0] trace_vaddr;
        logic trace_vaddr_is_valid;
        logic trace_value_is_valid;
        logic [63:0] trace_value;
        logic [ROB_TAG_W-1:0] age;
        logic committed;
    } st_entry;

    st_entry SQ [SQ_SIZE];

    logic [$clog2(SQ_SIZE)-1:0] sq_head;
    logic [$clog2(SQ_SIZE)-1:0] sq_tail;

    logic receive_new_data;
    logic write_new_data;    

    logic DBG;

    initial begin
        // if (!$value$plusargs("SQDEBUG=%b", DBG)) begin
        DBG = 0;
        // end
    end

    //assign ready_out = (curr_entries!={SQ_SIZE{1'b1}})|resolve|write_new_data;
    //assign receive_new_data = ready_out&trace_valid;
    assign payload_ready_o = (curr_entries!={SQ_SIZE{1'b1}})|write_new_data;
    assign receive_new_data = payload_ready_o&payload_valid_i;

    // TODO: Just assume data can be committed once queue full and resolved at head of queue?
    logic head_commit_now;
    assign head_commit_now = commit_valid && curr_entries[sq_head] && (commit_tag == SQ[sq_head].trace_id);
    assign valid_out = (curr_entries!={SQ_SIZE{1'b0}}&&(!lq_head_valid||lq_head_age-SQ[sq_head].age<16))&&
                       !curr_unresolved[sq_head] && (SQ[sq_head].committed || head_commit_now);
    assign write_new_data = valid_out & ready_in;
    assign write_vaddr = SQ[sq_head].trace_vaddr;
    assign write_value = SQ[sq_head].trace_value;

    logic [SQ_SIZE-1:0] tag_matching;

    logic [SQ_SIZE-1:0] tailmask;
    always_ff @(posedge clk_in) begin
        if(rst || flush) begin
            sq_head<=0;
            sq_tail<=0;
            curr_entries <= '0;
            tailmask <= '0;
            for (int j = 0; j < SQ_SIZE; ++j) begin
                SQ[j] <= '0;
            end
        end else begin
            if (cdb_i.valid) begin
                // resolve values here (possibly)
                int i;
                for (i = 0; i < SQ_SIZE; ++i) begin
                    if (!SQ[i].trace_vaddr_is_valid
                        && SQ[i].trace_vaddr[ROB_TAG_W-1:0] == cdb_i.tag) begin
                        SQ[i].trace_vaddr <= cdb_i.value[47:0];
                        SQ[i].trace_vaddr_is_valid <= 1'b1;
                    end

                    if (!SQ[i].trace_value_is_valid
                        && SQ[i].trace_value[ROB_TAG_W-1:0] == cdb_i.tag) begin
                        SQ[i].trace_value <= cdb_i.value;
                        SQ[i].trace_value_is_valid <= 1'b1;
                    end
                end
            end

            if (commit_valid) begin
                for (int i = 0; i < SQ_SIZE; ++i) begin
                    if (curr_entries[i] && (SQ[i].trace_id == commit_tag)) begin
                        SQ[i].committed <= 1'b1;
                    end
                end
            end
            
            if(receive_new_data) begin
                assert(payload_valid_i);
                assert(payload_i.src1_valid);
                assert(payload_i.src2_valid);
                if (payload_i.fu_select == FU_MEM && payload_i.fu_op == OP_STORE) begin
                    curr_entries[sq_tail] <= 1'b1;
                    SQ[sq_tail].trace_id <= payload_i.dest_tag; // rob destination
                    
                    // for now, i'm going to assume that src1 is addr
                    // and src2 is value
                    if (payload_i.src1_ready)
                        SQ[sq_tail].trace_vaddr <= payload_i.src1_value[47:0];
                    else
                        SQ[sq_tail].trace_vaddr <= { {(48-ROB_TAG_W){1'b0}}, payload_i.src1_tag};
                        
                    if (payload_i.src2_ready)
                        SQ[sq_tail].trace_value <= payload_i.src2_value;
                    else
                        SQ[sq_tail].trace_value <= { {(64-ROB_TAG_W){1'b0}}, payload_i.src2_tag};
                    SQ[sq_tail].trace_vaddr_is_valid <= payload_i.src1_ready;
                    SQ[sq_tail].trace_value_is_valid <= payload_i.src2_ready;
                    SQ[sq_tail].age <= payload_i.dest_tag; // rob dst doubles as age
                    SQ[sq_tail].committed <= 1'b0;
                    
                    sq_tail<=sq_tail+1;
                    if(sq_tail==0) begin
                        tailmask <= {{SQ_SIZE-1{1'b0}},1'b1};
                    end else begin
                        tailmask[sq_tail] <= 1'b1;
                    end

                end
                /*
                if(resolve) begin
                    if(tag_matching != {SQ_SIZE{1'b0}}) begin
                        logic [$clog2(SQ_SIZE)-1:0] addr;
                        int result;
                        result = msb_runtime(tag_matching);
                        addr=result[$clog2(SQ_SIZE)-1:0];
                        if(trace_vaddr_is_valid) begin
                            SQ[addr].trace_vaddr<=trace_vaddr;
                            SQ[addr].trace_vaddr_is_valid<=1'b1;
                        end
                        if(trace_value_is_valid) begin
                            SQ[addr].trace_value_is_valid<=1'b1;
                            SQ[addr].trace_value<=trace_value;
                        end
                    end
                end else begin
                    if(write_new_data) begin
                        if(sq_head != sq_tail) begin
                            curr_entries[sq_head]<=1'b0;
                        end
                        sq_head<=sq_head+1;
                    end
                    curr_entries[sq_tail] <= 1'b1;
                    SQ[sq_tail].trace_id<=trace_id;
                    SQ[sq_tail].trace_vaddr<=trace_vaddr;
                    SQ[sq_tail].trace_vaddr_is_valid<=trace_vaddr_is_valid;
                    SQ[sq_tail].trace_value_is_valid<=trace_value_is_valid;
                    SQ[sq_tail].trace_value<=trace_value;
                    SQ[sq_tail].age<=age;
                    sq_tail<=sq_tail+1;
                    if(sq_tail==0) begin
                        tailmask <= {{SQ_SIZE-1{1'b0}},1'b1};
                    end else begin
                        tailmask[sq_tail] <= 1'b1;
                    end
               end
                */
            end else if(write_new_data) begin
                curr_entries[sq_head]<=1'b0;
                sq_head<=sq_head+1;
            end
        end
    end

    logic [SQ_SIZE-1:0] curr_unresolved;
    logic [SQ_SIZE-1:0] older_store_mask;
    logic [SQ_SIZE-1:0] conflict_result;
    logic [SQ_SIZE-1:0] current_store_mask;
    logic [SQ_SIZE-1:0] curr_entries;
    logic [SQ_SIZE-1:0] match_result;
    
    genvar i;
    generate
    for (i=0;i<SQ_SIZE;i++) begin: match_addresses
        assign older_store_mask[i] = curr_entries[i] & (load_age-SQ[i].age<16);
        assign match_result[i] = older_store_mask[i] & SQ[i].trace_vaddr_is_valid & (SQ[i].trace_vaddr==search_addr);
        assign curr_unresolved[i] = curr_entries[i]&(!SQ[i].trace_vaddr_is_valid|!SQ[i].trace_value_is_valid);
        assign conflict_result[i] = older_store_mask[i] & !SQ[i].trace_vaddr_is_valid;
        //assign tag_matching[i] = curr_entries[i]&(SQ[i].trace_id==trace_id);
    end
    endgenerate

    assign current_store_mask = match_result | conflict_result;
    always_comb begin
        logic [$clog2(SQ_SIZE)-1:0] value_index;
        int result;
        found = current_store_mask!={SQ_SIZE{1'b0}};
        if(found) begin
            if(sq_head<sq_tail) begin
                result=msb_runtime(current_store_mask);
            end else begin
                if ((current_store_mask&tailmask)!={SQ_SIZE{1'b0}}) begin
                    result=msb_runtime(current_store_mask&tailmask);
                end else begin
                    result=msb_runtime(current_store_mask);
                end
            end
            value_index=result[$clog2(SQ_SIZE)-1:0];
            resolved = match_result[value_index] & !curr_unresolved[value_index];
            search_value = SQ[value_index].trace_value;
        end else begin
            value_index=0;
            resolved = 1'b0;
            search_value=0;
            result=0;
        end
    end
endmodule

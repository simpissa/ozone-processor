`timescale 1ns / 1ps
typedef struct packed {
    logic [3:0] trace_id;
    logic [47:0] trace_vaddr;
    logic trace_vaddr_is_valid;
    logic trace_value_is_valid;
    logic [63:0] trace_value;
    logic [4:0] age;
} st_entry;
module store_queue #(parameter int SQ_SIZE=8)(
    input logic rst,           // reset
    input logic clk_in,        // clock
    
    // Interacting with trace
    input logic valid_trace,         // input trace is valid
    output logic ready_out,           // ready to receive new input trace
    // Data
    input logic [3:0] trace_id,
    input logic [47:0] trace_vaddr,
    input logic trace_vaddr_is_valid,
    input logic trace_value_is_valid,
    input logic [63:0] trace_value,
    input logic resolve,
    input logic [4:0] age,      // Current age

    
    // Interacting with read queue
    input logic [47:0] search_addr,
    input logic [4:0] load_age,      // Age of load

    output logic found, // 1 if address found, 0 if not found
    output logic resolved, // if found: 0 if unresolved, 1 if valid value
    output logic [63:0] search_value,


    // Note sure when can commit stores, should be given by ROB
    // Interacting with L1 cache
    output logic [47:0] write_vaddr,
    output logic [63:0] write_value,
    input logic ready_in,
    output logic valid_out
);
    st_entry SQ [SQ_SIZE];

    logic [$clog2(SQ_SIZE)-1:0] sq_head;
    logic [$clog2(SQ_SIZE)-1:0] sq_tail;

    logic receive_new_data;
    logic write_new_data;    

    assign ready_out = (curr_entries!={SQ_SIZE{1'b1}})|resolve|write_new_data;
    assign receive_new_data = ready_out&valid_trace;

    // TODO: Just assume data can be committed once queue full and resolved at head of queue?
    assign valid_out = (curr_entries=={SQ_SIZE{1'b1}}|curr_entries!={SQ_SIZE{1'b0}}&age-SQ[sq_head].age>=16)&!curr_unresolved[sq_head];
    assign write_new_data = valid_out & ready_in;
    assign write_vaddr = SQ[sq_head].trace_vaddr;
    assign write_value = SQ[sq_head].trace_value;

    logic [SQ_SIZE-1:0] tag_matching;

    logic [SQ_SIZE-1:0] tailmask;
    always_ff @(posedge clk_in) begin
        if(rst) begin
            sq_head<=0;
            sq_tail<=0;
        end else begin
            if(receive_new_data) begin
                if(resolve) begin
                    if(tag_matching != {SQ_SIZE{1'b0}}) begin
                        logic [$clog2(SQ_SIZE)-1:0] addr;
                        int result;
                        result = $clog2({1'b0,tag_matching}+1)-1;
                        addr=result[$clog2(SQ_SIZE)-1:0];
                        SQ[addr].trace_vaddr<=trace_vaddr;
                        SQ[addr].trace_vaddr_is_valid<=trace_vaddr_is_valid;
                        SQ[addr].trace_value_is_valid<=trace_value_is_valid;
                        SQ[addr].trace_value<=trace_value;
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
            end else if(write_new_data) begin
                curr_entries[sq_head]<=1'b0;
                sq_head<=sq_head+1;
            end
        end
    end

    logic [SQ_SIZE-1:0] curr_unresolved;
    logic [SQ_SIZE-1:0] current_store_mask;
    logic [SQ_SIZE-1:0] curr_entries;
    logic [SQ_SIZE-1:0] match_result;
    
    genvar i;
    generate
    for (i=0;i<SQ_SIZE;i++) begin: match_addresses
        assign match_result[i] = curr_entries[i]&(load_age-SQ[i].age<16)&(SQ[i].trace_vaddr==search_addr);
        assign curr_unresolved[i] = curr_entries[i]&(!SQ[i].trace_vaddr_is_valid|!SQ[i].trace_value_is_valid);
        assign tag_matching[i] = curr_entries[i]&(SQ[i].trace_id==trace_id);
    end
    endgenerate

    assign current_store_mask = match_result|curr_unresolved;
    always_comb begin
        logic [$clog2(SQ_SIZE)-1:0] value_index;
        int result;
        found = current_store_mask!={SQ_SIZE{1'b0}};
        if(found) begin
            if(sq_head<sq_tail) begin
                result=$clog2({1'b0,current_store_mask}+1)-1;
            end else begin
                if ((current_store_mask&tailmask)!={SQ_SIZE{1'b0}}) begin
                    result=$clog2({1'b0,current_store_mask&tailmask}+1)-1;
                end else begin
                    result=$clog2({1'b0,current_store_mask}+1)-1;
                end
            end
            value_index=result[$clog2(SQ_SIZE)-1:0];
            resolved = !curr_unresolved[value_index];
            search_value = SQ[value_index].trace_value;
        end else begin
            value_index=0;
            resolved = 1'b0;
            search_value=0;
            result=0;
        end
    end
endmodule

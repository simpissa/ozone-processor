typedef struct packed {
    logic [3:0] trace_id;
    logic [47:0] trace_vaddr;
    logic trace_vaddr_is_valid;
    logic trace_value_is_valid;
    logic [63:0] trace_value;
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
    input logic [4:0] age,      // Age of trace

    
    // Interacting with read queue
    input logic [47:0] search_addr,
    input logic [4:0] load_age,      // Age of load

    output logic found, // 1 if address found, 0 if not found
    output logic resolved, // if found: 0 if unresolved, 1 if valid value
    output logic [63:0] search_value


    // Note sure when can commit stores, should be given by ROB
    // Interacting with L1 cache
    output logic [47:0] write_vaddr,
    input logic ready_in,
    output logic valid_out,

);
    st_entry SQ [SQ_SIZE];

    logic [$clog2(SQ_SIZE)-1:0] sq_head;
    logic [$clog2(SQ_SIZE)-1:0] sq_tail;

    logic receive_new_data;
    logic [SQ_SIZE-1:0] curr_entries;
    

    assign ready_out = curr_entries!={SQ_SIZE-1{1'b1}};
    assign receive_new_data = ready_out&valid_trace;
    always_ff(@posedge clk_in) begin
        if(reset) begin
            sq_head<=0;
            sq_tail<=0;
        end else begin
            if(receive_new_data) begin
                curr_entries[sq_tail] <= 1'b1;
                SQ[sq_tail].trace_id<=trace_id;
                SQ[sq_tail].trace_vaddr<=trace_vaddr;
                SQ[sq_tail].trace_vaddr_is_valid<=trace_vaddr_is_valid;
                SQ[sq_tail].trace_value_is_valid<=trace_value_is_valid;
                SQ[sq_tail].trace_value<=trace_value;
                sq_tail<=sq_tail+1;
            end
        end
    end

    assign curr_sq_tail = sq_tail;
    logic [47:0] search_vaddr;
    logic [SQ_SIZE-1:0] match_result;
    logic [SQ_SIZE-1:0] curr_unresolved;
    logic [SQ_SIZE-1:0] stopping_values;
    assign stopping_values= curr_unresolved|match_result;
    genvar i;
    generate
    for (i=0;i<SQ_SIZE;i++) begin: match_addresses
        assign match_result[i] = curr_entries[i]&(SQ[i].trace_vaddr==search_vaddr);
        assign curr_unresolved[i] = curr_entries[i]&(!SQ[i].trace_vaddr_is_valid|!SQ[i].trace_value_is_valid);
    end
    endgenerate

    logic [SQ_SIZE-1:0] previous_store_mask;
    logic [$clog2(SQ_SIZE)-1:0] new_prev_tail;
    logic [$clog2(SQ_SIZE)-1:0] value_index;
    always_comb begin
        new_prev_tail=prev_sq_tail-sq_head;
        if (sq_head!=sq_tail) begin
            previous_store_mask = {(match_result|curr_unresolved)[SQ_SIZE-1:sq_head],[sq_head-1:0]};
        end else begin
            previous_store_mask = match_result|curr_unresolved;
        end
        if(new_prev_tail<sq_head||new_prev_tail>sq_tail||{SQ_SIZE-new_prev_tail{1'b0},{new_prev_tail{1'b1}}}&previous_store_mask=={SQ_SIZE{1'b0}}) begin
            found = 1'b0;
        end else begin
            found = 1'b1;
            value_index=$clog2({SQ_SIZE-new_prev_tail{1'b0},{new_prev_tail{1'b1}}}&previous_store_mask)-1+sq_head;
            if (curr_unresolved[value_index]) begin
                resolved=1'b0;
            end else begin
                resolved=1'b1;
                search_value = SQ[value_index].trace_value;
            end
        end
    end
endmodule

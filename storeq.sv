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

    
    // TODO: I think we also need a way for SQ to alert a subset of load instructions to retry
    // Interacting with read queue
    input logic [47:0] search_addr,
    input logic valid_to_search,
    output logic ready_to_search,

    output logic found, // 1 if found, 0 if not found
    output logic unresolved, // if found: 1 if unresolved, 0 if valid
    output logic [63:0] search_value,
    output logic valid_search_value,
    input logic ready_search_value


    // Writes supposed to be done once ROB retires them, not sure if should implement here
    // or how to determine when to pop queue head?
    // Interacting with L1 cache
    //output logic [47:0] write_vaddr,
    //input logic ready_in,
    //output logic valid_out,

);
    
    
endmodule

typedef enum logic[2:0] {
    OP_MEM_LOAD = 0, // perform a memory load
    OP_MEM_STORE = 1, // send a memory store
    OP_MEM_RESOLVE = 2, // resolve an unresolved address
    OP_TLB_FILL = 4 // fill a line of the TLB 
} op_e;
`timescale 1ns / 1ps
module storeq_tb #(parameter int SQ_SIZE = 8) ();
    logic rst;           // reset
    logic clk_in;        // clock
    
    // Interacting with trace
    logic valid_trace;         // trace is valid
    logic ready_out;           // ready to receive new trace
    // Data
    logic [3:0] trace_id;
    logic [47:0] trace_vaddr;
    logic trace_vaddr_is_valid;
    logic trace_value_is_valid;
    logic [63:0] trace_value;
    logic resolve;
    logic [4:0] age;      // Age of trace

    
    // Interacting with read queue
    logic [47:0] search_addr;
    logic [4:0] load_age;      // Age of load

    logic found; // 1 if address found, 0 if not found
    logic resolved; // if found: 0 if unresolved, 1 if valid value
    logic [63:0] search_value;


    // Note sure when can commit stores, should be given by ROB
    // Interacting with L1 cache
    logic [47:0] write_vaddr;
    logic [63:0] write_value;
    logic [3:0] write_id;
    logic ready_in;
    logic nack_in;
    logic finished_in;
    logic tlb_fill;
    logic valid_out;

    store_queue #(.SQ_SIZE(SQ_SIZE)) asdf (
        .rst(rst),           // reset
        .clk_in(clk_in),        // clock
        
        // Interacting with trace
        .valid_trace(valid_trace),         // trace is valid
        .ready_out(ready_out),           // ready to receive new trace
        // Data
        .trace_id(trace_id),
        .trace_vaddr(trace_vaddr),
        .trace_vaddr_is_valid(trace_vaddr_is_valid),
        .trace_value_is_valid(trace_value_is_valid),
        .trace_value(trace_value),
        .resolve(resolve),
        .age(age),      // Age of trace

        
        // Interacting with read queue
        .search_addr(search_addr),
        .load_age(load_age),      // Age of load

        .found(found), // 1 if address found, 0 if not found
        .resolved(resolved), // if found: 0 if unresolved, 1 if valid value
        .search_value(search_value),


        // Note sure when can commit stores, should be given by ROB
        // Interacting with L1 cache
        .write_vaddr(write_vaddr),
        .write_value(write_value),
        .write_id(write_id),
        .ready_in(ready_in),
        .nack_in(nack_in),
        .finished_in(finished_in),
        .tlb_fill(tlb_fill),
        .valid_out(valid_out)
    );

    reg [179:0] trace_line; // Every test vectors is exactly this long
    integer fd;  // file descriptor

    initial begin
        clk_in = 0;
        forever begin
            #5 clk_in = ~clk_in;
        end
        //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    end

    //initial block...this is our test simulation
    initial begin
        fd = $fopen("sqtests.txt", "r");  // STUDENTS: Edit me to edit your test vector
        // Set initial values
        rst = 0;
        @(posedge clk_in);
        rst = 1;
        @(posedge clk_in);
        rst = 0;

        while (!$feof(
            fd
        )) begin : test_loop
            // Get next line
            $fscanf(fd, "%b\n", trace_line);
            trace_id = trace_line[51:48];
            trace_vaddr = trace_line[47:0];
            trace_vaddr_is_valid = trace_line[55]; // only relevant to mem operations
            trace_value_is_valid = trace_line[120]; // only relevant to store operations
            trace_value = trace_line[119:56]; // only relevant to store operations
            search_addr = trace_line[168:121];
            load_age = trace_line[173:169];
            resolve = trace_line[174];
            age = trace_line[179:175];

            while (!ready_out) begin
                @(posedge clk_in); // wait for FPM to be ready to consume data
            end
            @(negedge clk_in)
            valid_trace = 1;
            @(negedge clk_in); // FPM should consume data by this time
            valid_trace = 0;
            trace_id = 'x;
            trace_vaddr = 'x;
            trace_vaddr_is_valid = 'x;
            trace_value_is_valid = 'x;
            trace_value = 'x;

            while (!ready_out) begin
                @(posedge clk_in);  // wait for FPM to have a valid output
            end
            $display(
                "found: %b, resolved: %b, search_value: %b, write_vaddr: %b, write_value: %b, valid_out: %b",found,resolved,search_value,write_vaddr,write_value,valid_out
            );
        end : test_loop
        $fclose(fd);
        $finish;
    end

endmodule : storeq_tb
`default_nettype wire
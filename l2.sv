//5 cycle request to response
//4 ways, pipt, write-back, 4 mshr
//inclusive (l1 contents are in l2)
//30-bit paddr
module l2cache #(
    parameter int PADDR_W = 30,
    parameter int BLOCK_SIZE = 64,
    parameter int NUM_WAYS = 4,
    parameter int CAPACITY = 4096,
    parameter int NUM_MSHRS = 4,
    parameter int MSHR_QUEUE_SIZE = 4,
    parameter int ID_LENGTH = 4
) (
    input logic clk,
    input logic rst,
    
    // Query from L1
    input logic req_valid,
    input logic req_rw,
    input logic [PADDR_W-1:0] req_paddr,
    input logic [BLOCK_SIZE*8-1:0] req_data,
    input logic [ID_LENGTH-1:0] query_id,
    output logic ready_for_input,

    // Answering L1
    // Assume L1 always ready to accept data from L2
    output logic resp_valid,
    output logic [BLOCK_SIZE*8-1:0] resp_data,
    output logic [ID_LENGTH-1:0] output_id,
    
    // TODO: communicate with sdram
);
    localparam int OFFSET_SIZE = $clog2(BLOCK_SIZE);
    localparam int NUM_SETS = CAPACITY / BLOCK_SIZE / NUM_WAYS;
    localparam int TAG_SIZE = PADDR_W-$clog2(NUM_SETS) - OFFSET_SIZE;

    typedef struct packed {
        logic [BLOCK_SIZE*8-1:0] data;
        logic valid;
        logic dirty;
        logic [$clog(NUM_WAYS)-1:0] age;
        logic in_mshr;  // Indicates if 
        logic [$clog(NUM_MSHRS)-1:0] mshr_index;    // Indicate index of corresponding MSHR
    } cache_line;

    typedef struct packed {
        cache_line set [NUM_WAYS];
        logic [$clog(NUM_WAYS)-1:0] oldest;
    } cache_set;

    cache_set cache [NUM_SETS];

    always_ff @(posedge clk_in) begin
        if(rst) begin
            ready_for_input<=1'b1;
            resp_valid <=1'b0;
            cache <= 0;
        end else begin
            if (ready_for_input && req_valid) begin
                // Accept input from L1

            end
        end
    end

endmodule



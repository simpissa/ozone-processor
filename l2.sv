//5 cycle request to response
//4 ways, pipt, write-back, 4 mshr
//inclusive (l1 contents are in l2)
//30-bit paddr - 6 for offset
module l2cache #(
    parameter int PADDR_W = 30,
    parameter int BLOCK_SIZE = 64,
    parameter int NUM_WAYS = 4,
    parameter int CAPACITY = 4096,
    parameter int NUM_MSHRS = 4,
    parameter int MSHR_QUEUE_SIZE = 4,
    parameter int ID_LENGTH = 4
) (
    localparam int OFFSET_SIZE = $clog2(BLOCK_SIZE);
    localparam int NUM_SETS = CAPACITY / BLOCK_SIZE / NUM_WAYS;
    localparam int WORD_ADDR_SIZE = PADDR_W - OFFSET_SIZE;
    localparam int TAG_SIZE = WORD_ADDR_SIZE-$clog2(NUM_SETS);

    input logic clk,
    input logic rst,
    
    // Query from L1
    input logic l1_req_valid,
    input logic l1_req_rw,
    input logic [WORD_ADDR_SIZE-1:0] l1_req_paddr,
    input logic [BLOCK_SIZE*8-1:0] l1_req_data,
    input logic [ID_LENGTH-1:0] l1_query_id,
    output logic l1_ready_for_input,

    // Answering L1
    // Assume L1 always ready to accept data from L2
    output logic l1_resp_valid,
    output logic [BLOCK_SIZE*8-1:0] l1_resp_data,
    output logic [ID_LENGTH-1:0] l1_output_id,
    

    // Query SDRAM
    output  logic           sdram_req_valid,
    input   logic           sdram_req_ready,
    output  logic           sdram_req_rw,          // 0 = read line, 1 = write line
    output  logic [WORD_ADDR_SIZE-1:0]  sdram_req_addr,        // byte address
    output  logic [BLOCK_SIZE*8-1:0] sdram_req_wdata,       // one full cache line

    // Answers from SDRAM
    input logic             sdram_resp_valid,
    input logic [BLOCK_SIZE*8-1:0] sdram_resp_rdata,
);
    // Cache
    typedef struct packed {
        logic valid;
        logic dirty;
        logic mshr; // Indicates if address currently in a MSHR
        logic [$clog2(NUM_MSHRS)-1:0] mshr_index;
        logic [TAG_SIZE-1:0] tag;
        logic [BLOCK_SIZE*8-1:0] data;
    } cache_line;

    typedef struct packed {
        cache_line set [NUM_WAYS];
        logic grid[NUM_WAYS][NUM_WAYS];
        logic [$clog2(NUM_WAYS)-1:0] oldest;
        logic [NUM_WAYS-1:0] zero;
    } cache_set;

    cache_set cache [NUM_SETS];
    genvar i,j;
    generate
        for (i=0;i<NUM_SETS;i++) begin: init_cache
            for(j=0;j<NUM_WAYS;j++) begin: init_zero
                assign cache[i].zero[j] = grid[j]==0;
            end
            assign cache[i].oldest = $clog2(zero&(~zero+1));
        end
    endgenerate

    
    // Stage 4 MSHRs
    typedef struct packed {
        logic write;    // 1 if write, 0 if read
        logic [WORD_ADDR_SIZE-1:0] addr;
        logic [BLOCK_SIZE*8-1:0] data;
        logic [ID_LENGTH-1:0] id;
    } mshr_entry;

    typedef struct packed {
        mshr_entry queue [MSHR_QUEUE_SIZE];
        logic [$clog2(MSHR_QUEUE_SIZE)-1:0] tail;
        logic [MSHR_QUEUE_SIZE-1:0] reads;  // Indicates where the read operations in mhsr are
        logic [MSHR_QUEUE_SIZE-1:0] writes;  // Indicates where the write operations in mhsr are
        logic [$clog2(NUM_WAYS)-1:0] cache_line_index;   // Index of corresponding cache line in cache set
    } mshr;

    mshr mshrs [NUM_MSHRS];
    logic [NUM_MSHRS-1:0] available_mshrs;
    logic [NUM_MSHRS-1:0] unavailable_mshrs;
    logic [NUM_MSHRS-1:0] drain_mhsrs;
    logic [$clog2(NUM_MSHRS)-1:0] querying_mshr;
    assign available_mshrs = ~unavailable_mshrs;


    typedef struct packed {
        logic [ID_LENGTH-1:0] id;
        logic [TAG_SIZE-1:0] tag;
        logic [$clog2(NUM_SETS)-1:0] set_index;
        logic [BLOCK_SIZE*8-1:0] data;
        logic write;
        logic valid;
    } general_info;

    // Stage 4 info
    general_info stage4;
    logic cache_hit;
    logic [$clog2(NUM_WAYS)-1:0] cache_line_index;

    // Stage 3 info
    general_info stage3;
    cache_line relevant_set;    // Info of cache set corresponding to address
    logic [NUM_WAYS-1:0] tag_comparison;    // Compare tags against current stage3 info
    logic [$clog2(NUM_WAYS)-1:0] forwarded_cache_line_index;// TODO
    logic forwarded_valid;
    genvar k;
    generate
        for(k=0;k<NUM_WAYS;k++) begin:compare_tags
            assign tag_comparison[k] = stage3.valid && stage3.tag == relevant_set.set[k].tag;
        end
    endgenerate

    // Stage 2 info
    general_info stage2;

    // Stage 1 info
    general_info stage1;

    always_ff @(posedge clk_in) begin
        if(rst) begin
            l1_ready_for_input<=1'b1;
            l1_resp_valid <=1'b0;
            cache <= 0;
            mshrs <= 0;
            unavailable_mshrs <= 0;
            stage1 <= 0;
            stage2 <= 0;
            stage3 <= 0;
            stage4 <= 0;
        end else begin
            // Stage 5: output
            // Outputs to L1 cache should be assigned, assume L1 always able to receive data.
            // Stage 5 is just the outputs to L1 cache

            // Stage 4: update cache lines/MSHRs
            logic sent_stage_5; // Keep track of if sent info to stage 5 yet
            sent_stage_5=1'b0;
            // Update MSHRs
            logic mshr_freed;
            mshr_freed = 1'b0;
            if(sdram_resp_valid) begin
                sent_stage_5 = 1'b1;
                l1_resp_data <= sdram_resp_rdata;
                l1_output_id <= mshrs[querying_mshr].queue[0].id;

                // TODO: update cache line with correct val if available
                if (mshrs[querying_mshr].reads == 1) begin
                    mshr_freed = 1'b1;
                end else begin
                    mshrs[querying_mshr].queue[0].data <= sdram_resp_rdata;
                    mshrs[querying_mshr].writes[0] <= 1'b1;
                    mshrs[querying_mshr].reads[0] <= 1'b0;
                end
            end

            // Check MSHRs for data to write to L1
            if(!sent_stage_5 && |drain_mhsrs) begin

            end
            // Always check if SDRAM is ready for new queries

            // Handle hit/miss and whether to add to MSHRs

            logic stall;    // Indicates whether or not to stall
            stall=stage4.valid&&(!cache_hit&&available_mshrs == 0||cache_hit&&sent_stage_5);
            
            l1_resp_valid<=sent_stage_5;

            if(!stall) begin
                // Stage 4: handling hit/miss and modifying cache
                logic [$clog2(NUM_WAYS)-1:0] target_line;
                target_line = cache_hit ? cache_line_index:cache[stage4.set_index].oldest;

                // Update LRU grid
                for(int l=0;l<NUM_WAYS;l++) begin
                    if(l==target_line) begin
                        cache[stage4.set_index].grid[l][l] <= 1'b0;
                    end else begin
                        cache[stage4.set_index].grid[target_line][l] <= 1'b1;
                        cache[stage4.set_index].grid[l][target_line] <= 1'b0;
                    end
                end
                cache[stage4.set_index].set[target_line].valid <= 1'b1;
                if(stage4.write) begin
                    cache[stage4.set_index].set[target_line].dirty <= 1'b1;
                    cache[stage4.set_index].set[target_line].data <= stage4.data;
                    if (!cache_hit) begin
                    end
                end else begin
                    if (cache_hit) begin
                        // Send read data to stage 5
                    end else begin
                        // Go to MSHR
                        
                    end
                end

                // Stage 3: compare tags, see if hit/miss
                stage4 <= stage3;
                if(stage3.tag == stage4.tag && stage3.set_index == stage4.set_index) begin
                    cache_hit <= 1'b1;
                    cache_line_index <= cache_line_index;
                end else begin
                    logic found_tag_match;
                    found_tag_match = |tag_comparison;
                    cache_hit <= forwarded_valid||found_tag_match;
                    cache_line_index <= forwarded_valid?forwarded_cache_line_index:(found_tag_match?$clog2(tag_comparison):0);
                end

                // Stage 2: get correct cache set
                stage3 <= stage2;
                relevant_set <= cache[stage2.set_index];
                if(stage2.tag == stage4.tag && stage2.set_index == stage4.set_index) begin
                    forwarded_cache_line_index<=cache_line_index;
                    forwarded_valid <= 1'b1;
                end else begin
                    forwarded_valid<=1'b0;
                end


                // Sending to stage 2
                stage2 <= stage1;
            end
            // Stage 1: get inputs, find tag, cache set
            if (ready_for_input && req_valid) begin
                // Accept input from L1
                stage1.id <= l1_query_id;
                stage1.tag <= l1_req_paddr[WORD_ADDR_SIZE-1:$clog2(NUM_SETS)];
                stage1.write <= l1_req_rw;
                stage1.data <= l1_req_data;
                stage1.valid <= 1'b1;
                stage1.set_index <= l1_req_paddr[$clog2(NUM_SETS)-1:0];
            end else if (!stall) begin
                stage1.valid <= 1'b0;
            end
            ready_for_input <= !stall;
        end
    end

endmodule
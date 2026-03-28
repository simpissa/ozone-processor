/* verilator lint_off WIDTHCONCAT */
`timescale 1ns / 1ps

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
    // prob easier to make this constant and pack to byte address with 0s
    output  logic [31:0]  sdram_req_addr,        // byte address 
    output  logic [BLOCK_SIZE*8-1:0] sdram_req_wdata,       // one full cache line

    // Answers from SDRAM. Always ready to receive answers from SDRAM
    input logic             sdram_resp_valid,
    input logic [BLOCK_SIZE*8-1:0] sdram_resp_rdata
);
    localparam int OFFSET_SIZE = $clog2(BLOCK_SIZE);
    localparam int NUM_SETS = CAPACITY / BLOCK_SIZE / NUM_WAYS;
    localparam int WORD_ADDR_SIZE = PADDR_W - OFFSET_SIZE;
    localparam int TAG_SIZE = WORD_ADDR_SIZE-$clog2(NUM_SETS);

    // Cache
    typedef struct packed {
        logic valid;
        logic dirty;
        logic in_mshr; // Indicates if address currently in a MSHR
        logic [$clog2(NUM_MSHRS)-1:0] mshr_index;
        logic [TAG_SIZE-1:0] tag;
        logic [BLOCK_SIZE*8-1:0] data;
    } cache_line;

    typedef struct packed {
        cache_line [NUM_WAYS-1:0] set;
        logic [NUM_WAYS-1:0][NUM_WAYS-1:0] grid;
    } cache_set;

    cache_set [NUM_SETS-1:0] cache;
    logic [NUM_SETS-1:0][NUM_WAYS-1:0] zero;
    logic [NUM_SETS-1:0][$clog2(NUM_WAYS)-1:0] oldest;
    genvar i,j;
    generate
        for (i=0;i<NUM_SETS;i++) begin: init_cache
            for(j=0;j<NUM_WAYS;j++) begin: init_zero
                assign zero[i][j] = (cache[i].grid[j] == '0);
            end
            assign oldest[i] = $clog2(NUM_WAYS)'($clog2(zero[i]&(~zero[i]+1)));
        end
    endgenerate

    
    // Stage 4 MSHRs
    typedef struct packed {
        logic [BLOCK_SIZE*8-1:0] data;
        logic [ID_LENGTH-1:0] id;
    } mshr_entry;

    typedef struct packed {
        mshr_entry [MSHR_QUEUE_SIZE-1:0] queue;
        logic [$clog2(MSHR_QUEUE_SIZE)-1:0] tail;
        logic [MSHR_QUEUE_SIZE-1:0] reads;  // Indicates where the read operations in mhsr are
        logic [$clog2(NUM_WAYS)-1:0] cache_line_index;   // Index of corresponding cache line in cache set
        logic [TAG_SIZE-1:0] tag;
        logic [$clog2(NUM_SETS)-1:0] set_index;
        logic [BLOCK_SIZE*8-1:0] latest_value;  // Keep track of latest store into queue
        logic valid_value;
    } mshr;

    // Since SDRAM answers one at a time, assign MSHRs as circular buffer to avoid starvation
    mshr [NUM_MSHRS-1:0] mshrs;
    logic [NUM_MSHRS-1:0] available_mshrs;
    logic [NUM_MSHRS-1:0] unavailable_mshrs;
    logic [NUM_MSHRS-1:0] drain_mhsrs;
    logic [$clog2(NUM_MSHRS)-1:0] head_mshr;    // MSHR entry currently being queried
    logic [$clog2(NUM_MSHRS)-1:0] tail_mshr;
    logic [$clog2(NUM_MSHRS)-1:0] current_drain_mshr;   // MSHR to drain
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
    logic pending_evict;    // 1 if waiting for cycle where can send evict store to SDRAM

    // Stage 3 info
    general_info stage3;
    cache_set relevant_set;    // Info of cache set corresponding to address
    logic [NUM_WAYS-1:0] tag_comparison;    // Compare tags against current stage3 info
    logic [$clog2(NUM_WAYS)-1:0] forwarded_cache_line_index;
    logic forwarded_valid;
    genvar k;
    generate
        for(k=0;k<NUM_WAYS;k++) begin:compare_tags
            assign tag_comparison[k] = (relevant_set.set[k].valid||relevant_set.set[k].in_mshr) && stage3.tag == relevant_set.set[k].tag;
        end
    endgenerate

    // Stage 2 info
    general_info stage2;

    // Stage 1 info
    general_info stage1;

    always_ff @(posedge clk) begin
        if(rst) begin
            l1_ready_for_input<=1'b1;
            l1_resp_valid <=1'b0;
            cache <= '0;
            mshrs <= '0;
            unavailable_mshrs <= '0;
            drain_mhsrs <= '0;
            stage1 <= '0;
            stage2 <= '0;
            stage3 <= '0;
            stage4 <= '0;
            head_mshr <= '0;
            tail_mshr <= '0;
            current_drain_mshr <= '0;
            pending_evict <= 1'b0;
        end else begin
            logic sent_stage_5; // Keep track of if sent info to stage 5 yet
            logic mshr_to_cache;    // Transitioning from mshr to cache
            logic [BLOCK_SIZE*8-1:0] mshr_to_cache_data;
            logic next_pending_evict;
            logic can_query;
            logic eviction;
            logic [$clog2(NUM_MSHRS)-1:0] target_mshr;
            logic clearing_same_mshr;
            logic stall;    // Indicates whether or not to stall
            // Stage 5: output
            // Outputs to L1 cache should be assigned, assume L1 always able to receive data.
            // Stage 5 is just the outputs to L1 cache

            // Stage 4: update cache lines/MSHRs

            // Update MSHR after receiving info from sdram
            if(sdram_resp_valid) begin
                mshrs[head_mshr].queue[0].data <= sdram_resp_rdata;
                if (!mshrs[head_mshr].valid_value) begin
                    mshrs[head_mshr].valid_value <= 1'b1;
                    mshrs[head_mshr].latest_value <= sdram_resp_rdata;
                end
                drain_mhsrs[head_mshr] <= 1'b1;
            end

            sent_stage_5=1'b0;

            mshr_to_cache = 1'b0;
            // Check MSHRs for data to write to L1
            if(|drain_mhsrs) begin
                // Send read operation to stage 5
                logic [$clog2(MSHR_QUEUE_SIZE)-1:0] read_pos;
                read_pos = $clog2(MSHR_QUEUE_SIZE)'($clog2(mshrs[current_drain_mshr].reads&(~mshrs[current_drain_mshr].reads+1)));
                sent_stage_5 = 1'b1;
                l1_output_id <= mshrs[current_drain_mshr].queue[read_pos].id;
                if(read_pos == '0) begin
                    l1_resp_data <= mshrs[current_drain_mshr].queue[0].data;    // Data is from SDRAM answer
                end else begin
                    logic [$clog2(MSHR_QUEUE_SIZE)-1:0] prev;
                    prev = read_pos-1;
                    // Get forwarded data from last previous operation
                    l1_resp_data <= mshrs[current_drain_mshr].queue[prev].data;
                    mshrs[current_drain_mshr].queue[read_pos].data <= mshrs[current_drain_mshr].queue[prev].data;
                end
                if((mshrs[current_drain_mshr].reads ^ (1<<read_pos)) == '0) begin
                    // Clear out current mshr, forward value
                    mshrs[current_drain_mshr] <= '0;
                    mshr_to_cache = 1'b1;
                    mshr_to_cache_data = mshrs[current_drain_mshr].latest_value;
                    unavailable_mshrs[current_drain_mshr] <= 1'b0;
                    drain_mhsrs[current_drain_mshr] <= 1'b0;
                    current_drain_mshr <= current_drain_mshr + 1;
                end else begin
                    // Set up next drain of a read
                    mshrs[current_drain_mshr].reads[read_pos] <= 1'b0;
                end
            end

            next_pending_evict = pending_evict;
            // If SDRAM accepts input, can move onto requesting next input
            if (sdram_req_valid && sdram_req_ready) begin
                if(pending_evict) begin
                    next_pending_evict = 1'b0;  // SDRAM processing writing eviction
                end else begin
                    head_mshr <= head_mshr + 1; // SDRAM processing read miss
                end
            end
            
            // 1 if nobody else is querying SDRAM
            can_query = 1'b1;

            eviction = !cache_hit && cache[stage4.set_index].set[oldest[stage4.set_index]].valid && cache[stage4.set_index].set[oldest[stage4.set_index]].dirty;

            target_mshr = cache[stage4.set_index].set[oldest[stage4.set_index]].mshr_index;
            clearing_same_mshr = (current_drain_mshr == target_mshr) && mshr_to_cache&&cache[stage4.set_index].set[oldest[stage4.set_index]].in_mshr;
            stall=stage4.valid&&(!cache_hit&&available_mshrs == '0||!stage4.write&&sent_stage_5&&(cache_hit&&cache[stage4.set_index].set[oldest[stage4.set_index]].valid||clearing_same_mshr)||eviction&&next_pending_evict);
            if(!stall) begin
                // Stage 4: handling hit/miss and modifying cache
                if (stage4.valid) begin
                    logic [$clog2(NUM_WAYS)-1:0] target_line;
                    target_line = cache_hit ? cache_line_index:oldest[stage4.set_index];

                    // Update LRU grid
                    for(int l=0;l<NUM_WAYS;l++) begin
                        if($clog2(NUM_WAYS)'(l)==target_line) begin
                            cache[stage4.set_index].grid[l][l] <= 1'b0;
                        end else begin
                            cache[stage4.set_index].grid[target_line][l] <= 1'b1;
                            cache[stage4.set_index].grid[l][target_line] <= 1'b0;
                        end
                    end
                    if (cache_hit&&cache[stage4.set_index].set[target_line].in_mshr) begin
                        if(stage4.write) begin
                            cache[stage4.set_index].set[target_line].dirty <= 1'b1;
                            if (clearing_same_mshr) begin
                                mshr_to_cache_data = stage4.data;
                            end else begin
                                // Add to MSHR queue
                                mshrs[target_mshr].queue[mshrs[target_mshr].tail].data <= stage4.data;
                                mshrs[target_mshr].queue[mshrs[target_mshr].tail].id <= stage4.id;
                                mshrs[target_mshr].latest_value <= stage4.data;
                                mshrs[target_mshr].valid_value <= 1'b1;
                                mshrs[target_mshr].tail <= mshrs[target_mshr].tail + 1;
                            end
                        end else begin
                            if ((mshrs[target_mshr].valid_value||clearing_same_mshr)&&sent_stage_5) begin
                                // Forward value
                                sent_stage_5 = 1'b1;
                                l1_resp_data<=clearing_same_mshr?mshr_to_cache_data:mshrs[target_mshr].latest_value;
                                l1_output_id <= stage4.id;
                            end else begin
                                // Add to MSHR queue
                                mshrs[target_mshr].queue[mshrs[target_mshr].tail].id <= stage4.id;
                                mshrs[target_mshr].reads[mshrs[target_mshr].tail] <= 1'b1;
                                mshrs[target_mshr].tail <= mshrs[target_mshr].tail + 1;
                            end
                        end
                    end else begin
                        if(stage4.write) begin
                            cache[stage4.set_index].set[target_line].valid <= 1'b1;
                            cache[stage4.set_index].set[target_line].dirty <= 1'b1;
                            cache[stage4.set_index].set[target_line].data <= stage4.data;
                        end else begin
                            if (cache_hit) begin
                                // Send read data to stage 5
                                sent_stage_5 = 1'b1;
                                l1_resp_data <= cache[stage4.set_index].set[target_line].data;
                                l1_output_id <= stage4.id;
                            end else begin
                                // Read miss, put read into a new MSHR and reserve spot in cache line
                                mshrs[tail_mshr].tag <= stage4.tag;
                                mshrs[tail_mshr].set_index <= stage4.set_index;
                                mshrs[tail_mshr].queue[0].id <= stage4.id;
                                mshrs[tail_mshr].tail <= mshrs[tail_mshr].tail + 1;
                                mshrs[tail_mshr].reads[0] <= 1'b1;
                                mshrs[tail_mshr].cache_line_index <= target_line;
                                cache[stage4.set_index].set[target_line].valid <= 1'b0;
                                cache[stage4.set_index].set[target_line].dirty <= 1'b0;
                                cache[stage4.set_index].set[target_line].in_mshr <= 1'b1;
                                cache[stage4.set_index].set[target_line].mshr_index <= tail_mshr;
                                cache[stage4.set_index].set[target_line].tag <= stage4.tag;
                                unavailable_mshrs[tail_mshr] <= 1'b1;
                                tail_mshr <= tail_mshr + 1;
                            end
                        end

                        if (eviction) begin
                            // Send eviction write to SDRAM
                            next_pending_evict = 1'b1;
                            can_query = 1'b0;
                            sdram_req_rw <= 1'b1;
                            sdram_req_addr <= {{(32-PADDR_W){1'b0}}, cache[stage4.set_index].set[target_line].tag, stage4.set_index, {OFFSET_SIZE{1'b0}}};
                            sdram_req_wdata <= cache[stage4.set_index].set[target_line].data;
                        end
                    end
                end

                // Stage 3: compare tags, see if hit/miss
                stage4 <= stage3;
                if(stage4.valid && stage3.tag == stage4.tag && stage3.set_index == stage4.set_index) begin
                    cache_hit <= 1'b1;
                    cache_line_index <= cache_line_index;
                end else begin
                    logic found_tag_match;
                    found_tag_match = |tag_comparison;
                    cache_hit <= forwarded_valid||found_tag_match;
                    cache_line_index <= forwarded_valid?forwarded_cache_line_index:(found_tag_match?$clog2(NUM_WAYS)'($clog2(tag_comparison)):'0);
                end

                // Stage 2: get correct cache set
                stage3 <= stage2;
                relevant_set <= cache[stage2.set_index];
                if(stage4.valid && stage2.tag == stage4.tag && stage2.set_index == stage4.set_index) begin
                    forwarded_cache_line_index<=cache_line_index;
                    forwarded_valid <= 1'b1;
                end else begin
                    forwarded_valid<=1'b0;
                end

                // Sending to stage 2
                stage2 <= stage1;
            end
            // Stage 1: get inputs, find tag, cache set
            if (l1_ready_for_input && l1_req_valid) begin
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

            if ((unavailable_mshrs^drain_mhsrs) != '0 && can_query) begin
                // Query read from a MSHR to SDRAM (make query using head_mshr info)
                sdram_req_rw <= 1'b0;
                sdram_req_addr <= {{(32-PADDR_W){1'b0}}, mshrs[head_mshr].tag,mshrs[head_mshr].set_index, {OFFSET_SIZE{1'b0}}};
                sdram_req_wdata <= mshrs[head_mshr].queue[0].data;
                can_query = 1'b0;
            end

            if (mshr_to_cache) begin
                cache[mshrs[current_drain_mshr].set_index].set[mshrs[current_drain_mshr].cache_line_index].data<= mshr_to_cache_data;
                cache[mshrs[current_drain_mshr].set_index].set[mshrs[current_drain_mshr].cache_line_index].valid<= 1'b1;
                cache[mshrs[current_drain_mshr].set_index].set[mshrs[current_drain_mshr].cache_line_index].in_mshr<= 1'b0;
            end

            l1_ready_for_input <= !stall;
            l1_resp_valid<=sent_stage_5;
            pending_evict <= next_pending_evict;
            sdram_req_valid <= !can_query;
        end
    end
endmodule

//psuedocode for modulse and pipelining

*toplevel inputs*

**from l1:**

    
    l1_req_valid //tells us if l1 resquest is stale
    l1_req_rw
    [29:0] l1_req_addr (maybe only need the tag/offset but L1 may just send everything)
    [511:0] l1_req_w_data
    [63:0] byte_enable //for pipelined caches, we need to make sure that when we get our response from the dram, we remember where we were meant to write to
    [63:0] l1_mshr_en
    [1:0] l1_mshr_id

    output l1_req_ready //ready for requests

    output l1_resp_valid
    [511:0] output l1_resp_data
    [1:0] output l1_resp_mshr_id //hey you sent a request for a mshr before, this is the one you're writing back to btw



from dram:

//**TODO**: look over in a bit

**pipeline register structs:**

    //syntax for struct in verilog is like in c

    //unpacked treat the structs as floating vectors, packing makes them contigous (idk why you'd unpack)


    typedef struct packed {
        fields
    } structname


    //register for input before s2 resolution


    typedef struct packed { // smth like 570 bits
        valid
        rw
        [29:0] paddr
        [19:0] tag
        [3:0] index
        [511:0] data
        [1:0] l1_mshr_id
        [63:0] byte_enable
    } pipe_pres2_t


    //register for input after s2 resolves


    typedef struct packed {
        valid
        rw
        [29:0] paddr
        [19:0] tag
        [3:0] index
        [511:0] data
        [1:0] l1_mshr_id
        [63:0] byte_enable
        //new
        hit
        [1:0] hit_way
        [511:0] hit_data
        [1:0] victim_way
        victim_dirty
        [29:0] victim_addr
    } pipe_posts2_t


**LRU stuff**


    lru_update_enable
    [3:0] lru_update_index
    [1:0] lru_update_way
    [3:0] lru_query_index
    [1:0] lru_victim


**MSHR stuff**

    mshr_req_valid
    [29:0] mshr_req_addr ///address of miss
    mshr_req_rw //r/w of miss
    mshr_primary //primary miss?
    mshr_secondary //secondary miss?
    mshr_stalling //mshr full
    [511:0] mshr_data //write data
    [63:0] mshr_byte_enable //bytes to write to
    [1:0] mshr_req_id //tells s3 where the mshr put entry
    [1:0] mshr_l1_req_id //l1 mshr to respond to


**cache_array**

    //this is a physically indexed, physically tagged, non-blocking, write-back cache, with 4KiB capacity (64B blocks), 4-ways, and 5-cycle latency. there are 4 MSHRs, so at most we can process 5 misses before we stall. cache dimensions (4 ways x 16 sets = 64 blocks). verilog allows us to write pack ararays kinda like the packed structs we used before, it's like


    logic [packed:dims] name [unpacked:dims]
    

    //but the packed dims are like the actual structs we're using, the unpacked dims give us iterations of those, kinda like a c array (i don't really think so bc in a c array you're 1. doing memory ops, not hardware ops and 2. wire synthesis is nothing like bit synthesis ;-;).

    //let's also remember, for now, our physical addresses are like

    //0 tag bits, 4 index bits, and 6 offset bits (that we don't use)

    //define our cache size: 64 blocks of 64B , 16 sets, 4 ways

module:

    module cache_array (
        [3:0] r_index,
        output [19:0] r_tag,
        output [511:0] r_data,
        output r_valid
        output r_dirty,
        [3:0] w_index,
        [1:0] w_way,
        [19:0] w_tag,
        [511:0] w_data,
        w_valid,
        w_dirty
    )
        [511:0] data_array [15:0] [3:0]; //we can parameterize this 
        [19:0] tag_array [15:0] [3:0];
        valid [15:0] [3:0];
        dirty [15:0] [3:0];

        //read: just fill out the data from the arrays
        always_comb begin
            for(int i = 0; i < 4; i++) begin
                r_tag[i] = tag_array[r_index][i];
                r_data[i] = data_array[r_index][i];
                r_valid[i] = valid[r_index][i];
                r_dirty[i] = dirty[r_index][i]
            end
        end

        //write: only do this on clk, but update data and tags and dirties and valids
        always_ff @(posedge clk) begin
            if(rw) begin
                tag_array[w_index][w_way] <= w_tag;
                data_array[w_index][w_way] <= w_data;  
                valid[w_index][w_way] <= w_valid;
                dirty[w_index][w_way] <= w_dirty;
            end
        end
    endmodule

**lru**

    //simple tree for each of the 16 sets to pick a way
    module tree_lru (
        lru_update_enable
        [3:0] lru_update_index
        [1:0] lru_update_way
        [3:0] lru_query_index
        output [1:0] lru_victim
    )
        [2:0] tree [15:0]

        //selection
        always_ff @(posedge clk) begin
            curr = 1'b0;
            for (int i = 0; i < 3; i++) begin
                curr = tree[lru_query_index][i] ? curr + 1 : curr - 1; //traverse tree to find victim
            end
            lru_victim <= curr;
        end

        //update
        always_ff @(posedge clk) begin
            if(lru_update_enable) begin
                case(lru_update_way)
                    2'b00: tree[lru_update_index] <= {1'b1, 1'b1, tree[update_index][0]};
                    2'b01: tree[lru_update_index] <= {1'b1, 1'b0, tree[update_index][0]};
                    2'b10: tree[lru_update_index] <= {1'b0, tree[update_index][1], 1'b1};
                    2'b11: tree[lru_update_index] <= {1'b0, tree[update_index][1], 1'b0};
            end
        end
        
    endmodule


**mshr**

    module mshr (
        mshr_req_valid
        [29:0] mshr_req_addr ///address of miss
        mshr_req_rw //r/w of miss
        output primary //primary miss?
        output secondary //secondary miss?
        output stalling //mshr full
        [511:0] mshr_data //write data
        [63:0] mshr_byte_enable //bytes to write to
        output [1:0] mshr_req_id //tells s3 where the mshr put entry
        [1:0] mshr_l1_req_id //l1 mshr to respond to
        
        //dram
        output dram_req_valid
        output [29:0] dram_req_addr
        dram_resp_valid
        [511:0] dram_resp_data

        //drain to l1
        output resp_valid
        output [511:0] resp_data
        output [1:0] resp_mshr_id

        //writeback to cache array
        output fill_wr_en
        output [29:0] fill_addr
        output [511:9] fill_data
        output [1:0] fill_way //in pipeline, this is victim lru
    )

christ this one sucks, luckily we only need to manage 4 mshrs, this means 4 entries at most, but both need their own cirular miss queue. for sake of there only being two entries, we're gonna use the array functionality of sysv because it'll compile a lot nicer than two modules, and it will make indexing into things much easier

    //missq entry struct
    typedef struct packed {
        logic valid;
        logic rw;
        logic [29:0] paddr;
        logic [511:0] wdata;
        logic [63:0] be;
    } mq_entry_t;

2 mshrs, we're gonna need to store the memory address and a miss queue, we're gonna go with a size of 8 for now, because it's kinda insane to miss on an address 8 times before getting a response from dram.

        //storage
        logic mshr_valid [3:0]
        logic mshr_filled [3:0]
        logic [29:0] mshr_addrs [3:0]
        logic [511:0] mshr_data [3:0]
        logic [1:0] l1_id [3:0]

        mq_entry_t miss_queues [3:0] [7:0]
        logic [2:0] mq_head [3:0]
        logic [2:0] mq_tail [3:0]

        //mshr gets latched internally

        //mshr update protocol:
        // 1. check against entries (CAM Style)
        //  1a. if match, check queue and r/w
        //  1b. if read and there's a write ahead (to the same bytes), forward the value
        //  1c. else, enqueue
        // 2. if not found, find empty 
        //  2a. fill entry, update bitmap, send request to dram
        // 3. if no empty, stall pipeline

        //mshr drain protocol
        // 1. response from dram handshake, find the correct entry
        // 2. handle the miss gracefully, update data cache, then fill l1 response
        // 3. drain the miss queue (perhaps just drain the entry)

        //forwards
        always_comb begin
            //defaults
            primary = 1'b0;
            secondary = 1'b0;
            stall = 1'b0;
            mshr_id = 2'b00;
            resp_valid = 1'b0;
            resp_data = 0;
            resp_mshr_id = '0;
            if(mshr_req_valid) begin
                for(int i = 0; i < 4; i++) begin //find mshr
                    if((mshr_addrs[i] == mshr_req_addr) && mshr_valid[i]) begin //secondary miss
                        secondary = 1'b1;
                        mshr_id = i[1:0];
                        if(mshr_req_rw) begin
                            for(int j = 0; j < 7; j++) begin //check associated q
                                if(|(miss_queues & miss_queues[i][j].be ) && mise_queues[i][j].valid && miss_queues[i][j].rw) begin //overlapping bytes
                                    resp_valid = 1'b1;
                                    resp_data = miss_queues[i][j].wdata;
                                    resp_mshr_id = l1_id[i];
                                end
                            end
                        end
                    end
                end
                //not secondary, find entry
                if(!secondary) begin
                    automatic logic found = 1'b0;
                    for (int i = 0; i < 4; i++) begin
                        if(!mshr_valid[i] && !found) begin
                            primary = 1'b1;
                            mshr_id = 1[1:0];
                            found = 1'b1;
                    end
                end
                if (!primary) stall = 1'b1;
            end
        end

        //alloc block back to cache array (put in pipeline)
        always_ff @(posedge clk) begin

        end

        //drain
        always_ff @(posedge clk) begin
            if(dram_resp_valid) begin
                for(int i = 0; i < 7; i++) begin
                    //invalidate miss q
                    miss_queue[i].valid = 1'b0;
                end
            end
        end
    endmodule

pipeline logic

//S1: latch data and extract tag/index for S2

pipe_pre2_t l0, l1;
pipe_posts2_ l2, l3, l4;

always_ff @(posedge clk) begin //latchin
    if(!stalling) begin
        l0.valid = l1_req_valid;
        l0.rw = l1_req_rw;
        l0.paadr = l1_req_addr;
        l0.tag = l1_req_addr[29:10];
        l0.index = l1_req_addr[9:6];
        l0.data = l1_req_data;
        l0.l1_mshr_id = l1_mshr_id;
        l0.byte_enable = byte_enable
    end
end

lru lru (
    lru_update_enable,
    lru_update_index,
    lru_update_way,
    lru_questy_index,
    lru_victim
)

cache_array cache (
    
)

//S2: hit/miss detection, data population, lru victim selection
always_ff @(posedge clk) begin
    //access/update cache array and lru unit

    

    lru_update_enable <=

    

    //latch
    l1.valid = l0.valid;
    l1.rw = l0.rw;
    l1.paddr = l0.paddr;
    l1.tag = l0.tag;
    l1.index = l1.index;
    l1.data = l0.data;
    l1.l1_mshr_id = l0.l1_mshr_id;
    l1.byte_enable = l0.byte_enable;
end


//hit/miss and data pop
always_comb begin
    //defaults (miss, no data)
    hit = 1'b0;
    hit_way = 2'b00;
    hit_data = '0;

    //search 
    for(int i = 0; i < 4; i++) begin
        if(valid[index][i] && tag_array[index][i] == tag) begin //valid data, right tag
            hit = 1'b1;
            hit_way = i[1:0];
            hit_data = data_array[index][i];
        end
    end
end

//victim selection


//S3: MSHR handling for misses, write logic (byte-enabled)

//S4: Writeback moment

//S5: Latch out

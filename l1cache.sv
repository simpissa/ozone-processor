`timescale 1ns / 1ps

module l1cache #(
	parameter int VADDR_W = 48,
  parameter int PADDR_W = 30,
  parameter int BLOCK_SIZE = 64,
  parameter int NUM_WAYS = 2,
  parameter int CAPACITY = 512,
  parameter int NUM_MSHRS = 2,
  parameter int MSHR_QUEUE_SIZE = 4,
  parameter int ID_LENGTH = 3 // TODO I jsut put 3 as default dont know actual id length
)(
	input  logic         clk,
	input  logic         reset,
  // lsq params
  input logic [VADDR_W-1:0] vaddr,
  input logic loadValid,
  input logic [ID_LENGTH-1:0] load_id,
  input logic [ID_LENGTH-1:0] store_id,
  input logic storeValid,
  input logic [63:0] store_data,
  output logic [ID_LENGTH-1:0] load_id_completed,
  output logic [ID_LENGTH-1:0] store_id_completed,

  output logic l1ready,
  output logic [63:0] data_out,
  output logic data_valid,

  // l2 params
  // Query L2
  output logic l2_req_valid, // our request is valid
  output logic l2_req_rw, // read/write operation associated with request (not sure which is which, needs to be worked out w/ l2)
  output logic [PADDR_W-6-1:0] l2_req_paddr, // physical addr associated w/ request
  output logic [511:0] l2_req_data, // data for write request
  output logic [ID_LENGTH-1:0] l2_query_id, // id on request 
  output logic l2_evict_valid,
  output logic [511:0] l2_evict_data,
  input logic l2_ready_for_resp, // is l2 ready for l1 request? the name contradicts with the fact this is an input imo

  // L2 Response
  input logic l2_resp_valid,
  input logic [511:0] l2_resp_data,
  input logic [ID_LENGTH-1:0] l2_resp_id,
  input logic [PADDR_W-1:0] l2_paddr,


  // tlb params
  input logic [PADDR_W-1:0] tlb_paddr_in,
  input logic tlb_paddr_ready,
  output logic [VADDR_W-1:0] tlb_vaddr_out,
  output logic tlb_vaddr_valid
);

  localparam int NUM_SETS = CAPACITY / BLOCK_SIZE / NUM_WAYS;
  localparam int TAG_SIZE = PADDR_W-($clog2(NUM_SETS) + $clog2(BLOCK_SIZE));

  typedef struct packed {
    logic [NUM_WAYS-1:0][BLOCK_SIZE*8-1:0] data;
  } data_arr_set;

  // TODO NUM_TAGS IN LINE IS BLOCK_SIZE / DATA_SIZE
  typedef struct packed {
    logic [NUM_WAYS-1:0][TAG_SIZE-1:0] data;
    logic [NUM_WAYS-1:0] valid;
    logic [NUM_WAYS-1:0] dirty;
    logic lru;
  } tag_arr_set;

  typedef struct packed {
    data_arr_set data_set; 
    tag_arr_set tag_set; 
    logic[VADDR_W-1:0] vaddr;
    logic[$clog2(BLOCK_SIZE)-1:0] block_offset;
    logic[63:0] store_data;
    logic[$clog2(NUM_SETS)-1:0] set_index;
    logic valid;
    logic is_store;
    logic[ID_LENGTH-1:0] instr_id;
  } stage2_info;

  typedef struct packed {
    logic[63:0] data; 
    logic [TAG_SIZE-1:0] tag; 
    logic[VADDR_W-1:0] vaddr;
    logic[PADDR_W-1:0] paddr;
    logic[63:0] store_data;
    logic[$clog2(NUM_WAYS)-1:0] way_store_index;
    logic[$clog2(NUM_SETS)-1:0] set_index;
    logic[$clog2(BLOCK_SIZE)-1:0] block_offset;
    logic miss;
    logic valid;
    logic is_store;
    logic[ID_LENGTH-1:0] instr_id;
  } stage3_info;

  
  data_arr_set data_arr[NUM_SETS-1:0];
  tag_arr_set tag_arr[NUM_SETS-1:0];

  task print_cache;
    $display("<------------------------------------- CACHE STATE --------------------------------------->\n");
    $display("|-----------------------------------------------------------------------------------------|");
    for (int i = 0; i < NUM_WAYS; ++i) begin
      $write("| %1s | %1s | %3s | %-7s | %-18s ", "V", "D", "LRU", "Tag", "Data");
    end
    $display("|");
    $display("|-----------------------------------------------------------------------------------------|");
    for (int i = 0; i < NUM_SETS; ++i) begin
      for (int j = 0; j < NUM_WAYS; ++j) begin
        $write("| %1b | %1b |  %1b  | 0x%05x | 0x%016x ", 
            tag_arr[i].valid[i],
            tag_arr[i].dirty[j],
            tag_arr[i].lru == 1'(j) ? 0'b1 : 0'b0,
            tag_arr[i].data[j],
            data_arr[i].data[j]
        );  
      end
      $display("|");
    end
    $display("|-----------------------------------------------------------------------------------------|");
  endtask

  data_arr_set stage1_data_set;
  tag_arr_set stage1_tag_set;
  data_arr_set stage2_data_set;
  tag_arr_set stage2_tag_set;

  logic stage2_blocked, stage3_blocked;

  stage2_info stage2;
  stage3_info stage3;

  // TODO SET ALL TO DEFAULT
  initial begin 
    // TODO initialize all data to 0
    // data_arr = 0;
    // tag_arr = 0;

    print_cache();
  end

  /**
  / Stage 1
  */
  logic is_valid;
  assign is_valid = storeValid | loadValid;
  assign tlb_vaddr_out = vaddr;
  assign tlb_vaddr_valid = (~reset) & (~stage3_blocked) & (~stage2_blocked) & (is_valid);
  logic[$clog2(BLOCK_SIZE)-1:0] block_offset;
  logic[$clog2(NUM_SETS)-1:0] set_index;

  assign block_offset = vaddr[$clog2(BLOCK_SIZE)-1:0];
  assign set_index = vaddr[$clog2(BLOCK_SIZE)+$clog2(NUM_SETS)-1:$clog2(BLOCK_SIZE)];

  always_comb begin

  end

  /*
  / Stage 2 Pipeline
  */
  always_ff @(posedge clk) begin
    if(~stage3_blocked && ~stage2_blocked) begin
      stage2.data_set <= data_arr[set_index];
      stage2.tag_set <= tag_arr[set_index];
      stage2.set_index <= set_index;
      stage2.block_offset <= block_offset;
      stage2.vaddr <= vaddr;
      stage2.store_data <= store_data;
      stage2.valid <= is_valid;
      stage2.is_store <= storeValid;
      if(storeValid) begin
        stage2.instr_id <= store_id;
      end else begin
        stage2.instr_id <= load_id;
      end
    end else begin
      stage2.valid <= 1'b0;
    end
  end

  /*
  / Stage 2
  */
  // TODO Verify tag logic i think there should be more tag bits
  logic[TAG_SIZE-1:0] paddr_tag;
  logic[NUM_WAYS-1:0] tag_comps;
  // Select data and tag to be passed onto the next stage
  logic[TAG_SIZE-1:0] tag_sel;
  logic[63:0] data_sel;
  logic[$clog2(NUM_WAYS)-1:0] way_index;
  logic miss;

  assign paddr_tag = tlb_paddr_in[PADDR_W-1:$clog2(NUM_SETS) + $clog2(BLOCK_SIZE)];
  assign stage2_blocked = ~(tlb_paddr_ready & ~stage3_blocked & stage2.valid);

  always_comb begin
    miss = 1'b1;
    tag_comps = 0;
    tag_sel = 0;
    data_sel = 0;
    way_index = 0;
    if(~stage2_blocked) begin
      for(int i = 0; i < NUM_WAYS; i++) begin
        tag_comps[i] = stage2.tag_set.data[i] == paddr_tag;
        if(tag_comps[i]) begin
          tag_sel = stage2.tag_set.data[i];
          way_index = ($clog2(NUM_WAYS))'(i);
          // Index in based off of what byte from block offset
          data_sel = stage2.data_set.data[i][8 * stage2.block_offset +: 64];
          miss = 1'b0;
        end
      end
    end
  end

  /*
  / Stage 3 Pipeline
  */
  always_ff @(posedge clk) begin
    if(~stage2_blocked) begin
      stage3.data <= data_sel;
      stage3.tag <= paddr_tag;
      stage3.vaddr <= stage2.vaddr;
      stage3.store_data <= stage2.store_data;
      stage3.miss <= miss;
      stage3.paddr <= tlb_paddr_in;
      stage3.valid <= stage2.valid;
      stage3.is_store <= stage2.is_store;
      stage3.way_store_index <= way_index;
      stage3.set_index <= stage2.set_index;
      stage3.block_offset <= stage2.block_offset;
      stage3.instr_id <= stage2.instr_id;
    end else begin
      stage3.valid <= 1'b0;
    end
  end

  logic should_stall_mshr;  // mshr full or busy
  logic[ID_LENGTH-1:0] mshr_id; // id for instruciton being fulfilled
  logic mshr_out_valid; // If outputs are valid
  logic mshr_is_store_out;
  logic[63:0] mshr_data_out; // store output
  logic[$clog2(BLOCK_SIZE)-1:0] mshr_offset; // Corresponding block offset

  mshr #(.NUM_ENTRYS(NUM_MSHRS),
        .QUEUE_SIZE(MSHR_QUEUE_SIZE),
        .PADDR_W(PADDR_W),
        .DATA_SIZE(64),
        .ID_SIZE(ID_LENGTH),
        .OFFSET_SIZE($clog2(BLOCK_SIZE)),
        .BLOCK_SIZE(BLOCK_SIZE)) mshr_module(
          .clk(clk),
          .store_data(stage3.store_data),
          .paddr(stage3.paddr),
          .id_in(stage3.instr_id),
          .miss(stage3.miss),
          .valid(stage3.valid),
          .l2_completed(l2_resp_valid),
          .l2_paddr(l2_paddr),
          .is_store(stage3.is_store),
          .stall(should_stall_mshr),
          .id_out(mshr_id),
          .write_out(mshr_data_out),
          .output_valid(mshr_out_valid),
          .offset_out(mshr_offset),
          .is_store_out(mshr_is_store_out)
        );

  assign stage3_blocked = should_stall_mshr;

  /*
  Wanted logic: 
    If l2 sends data, store it to the cache
    If the mshr has a load at the address start outputting data corresponding to the mshr
    If not, the output hits/load new things into the mshr
    the 3rd stage will get stalled if the mshr is pushing data or the mshrs are full and there is another miss
    loads can immediately be handled due to the stage 2 data pipe selection
    stores have an extra flipflop to store the value in
    l2 must get sent dirty data that is evicted for ram writeback
    l2 receives what address we received and if it missed
    l2 must provide us with the tag array as well to fill in
  */

  // TODO When we receive l2 data, should we wait for MSHR to output all the instructions to us, 
  //      or do we write all stores into a buffer in the mshr and instantly write all stores to the
  //      cache.
  //      On another note, should we let each mshr store a whole cache line so they can each work
  //      on a cache line at a time or do we leave that up to l1? We could also have 1 working
  //      cache line register that we load each respective mshr data into when received.

  always_comb begin
    data_valid = 1'b0;
    data_out = stage3.data;
    if(mshr_out_valid) begin
      if(mshr_is_store_out) begin
        // Store here if we want to dispense entire queue here
      end else begin
        // Output load here, loads must be done one at a time since their pins need output
        // We can do 1 at a time because regardless all instruciton id completions must be sent out
      end
    end else if(stage3.valid & ~stage3.miss) begin 
      // Output hit
      if(~stage3.is_store) begin
        // Presumably only handle loads since stores are handled in ff
        data_valid = 1'b1;
        data_out = stage3.data;
      end
    end else if(stage3.valid) begin 
      // MSHR modules auto handle the miss, l2 should be sent required miss data
    end else begin
      // Presumably output invalid because the stage is invalid and no other data is available out
    end
  end

  logic[$clog2(NUM_SETS)-1:0] l2_paddr_set = l2_paddr[$clog2(BLOCK_SIZE) +: $clog2(NUM_SETS)];
  logic[$clog2(NUM_WAYS)-1:0] way_evicted = tag_arr[l2_paddr_set].lru;
  logic[TAG_SIZE-1:0] l2_paddr_tag = l2_paddr[$clog2(BLOCK_SIZE) + $clog2(NUM_SETS) +: TAG_SIZE];
  
  // Update on a store
  always_ff @(posedge clk) begin
    // Update cache with normal state if not updating with l2
    // l2 should take priority with updating if on a miss, use mshr to determine
    if(l2_resp_valid) begin
      // Bring in the data into the cache, have seperate logic for outputting instrs
      // from mshr
      // lru way 0, evict and make 1 lru
      l2_evict_valid <= 1'b0;

      if(way_evicted == 1'b0) begin
        tag_arr[l2_paddr_set].lru <= 1'b1;
      end else begin        
        tag_arr[l2_paddr_set].lru <= 1'b0;
      end
      // Output line if dirty to update l2
      if(tag_arr[l2_paddr_set].dirty[way_evicted]) begin
        l2_evict_valid <= 1'b1;
        l2_evict_data <= data_arr[l2_paddr_set].data[way_evicted];
      end
      // Store l2 data in cache and set to clean and valid
      data_arr[l2_paddr_set].data[way_evicted] <= l2_resp_data;
      tag_arr[l2_paddr_set].data[way_evicted] <= l2_paddr_tag;
      tag_arr[l2_paddr_set].dirty[way_evicted] <= 1'b0;
      tag_arr[l2_paddr_set].valid[way_evicted] <= 1'b1;
    end else if(stage3.valid & ~stage3.miss & stage3.is_store) begin
      data_arr[stage3.set_index].data[stage3.way_store_index][stage3.block_offset*8+:64] <= stage3.store_data;
    end
  end
endmodule

// TODO MSHR Should feed loads forward if same offset
module mshr#(
  parameter int NUM_ENTRYS = 2,
	parameter int QUEUE_SIZE = 4,
  parameter int PADDR_W = 30,
  parameter int DATA_SIZE = 64,
  parameter int ID_SIZE = 3,
  parameter int OFFSET_SIZE = 6,
  parameter int BLOCK_SIZE = 64
)(
  input logic clk,
  input logic[DATA_SIZE-1:0] store_data,
  input logic[PADDR_W-1:0] paddr,
  input logic[ID_SIZE-1:0] id_in,
  input logic miss,
  input logic valid,
  input logic l2_completed,
  input logic[PADDR_W-1:0] l2_paddr,
  input logic is_store,

  output logic stall,
  output logic[ID_SIZE-1:0] id_out,
  output logic[DATA_SIZE-1:0] write_out,
  output logic[OFFSET_SIZE-1:0] offset_out,
  output logic output_valid,
  output logic is_store_out
);

  typedef struct packed {
    logic is_store;
    logic[ID_SIZE-1:0] id; // instruciton id
    logic[OFFSET_SIZE-1:0] block_offset;
    logic[DATA_SIZE-1:0] store_val;
  } queue_entry;

  typedef struct packed {
    queue_entry[QUEUE_SIZE-1:0] queue;
    logic[PADDR_W-1:0] address;
    logic occupied;
    logic[$clog2(QUEUE_SIZE)-1:0] head;
    logic[$clog2(QUEUE_SIZE)-1:0] tail;
    logic[$clog2(QUEUE_SIZE):0] count;
    logic should_drain;
  } mshr_entry;

  mshr_entry[NUM_ENTRYS-1:0] entries;

  logic entry_open;
  logic[$clog2(NUM_ENTRYS)-1:0] entry_index;
  logic match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] match_index;
  logic l2_match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] l2_match_index;

  // Global draining and drain entry index
  logic draining;
  logic[$clog2(NUM_ENTRYS)-1:0] drain_index;
  logic[$clog2(NUM_ENTRYS)-1:0] wanted_drain_index;
  logic[$clog2(NUM_ENTRYS)-1:0] theorized_drain_index;
  logic theorized_drain_index_valid;

  assign stall = draining;

  // Check to see if the entry exists.
  // If it does, check if queue full
  //  If it is stall
  //  If not add to queue
  // If entry dosnt exist, add or stall
  always_comb begin
    // Check if open entry or match
    entry_open = 1'b0;
    entry_index = 0;
    match_made = 1'b0;
    match_index = 0;
    l2_match_made = 1'b0;
    l2_match_index = 0;
    wanted_drain_index = 0;
    theorized_drain_index = 0;
    theorized_drain_index_valid = 1'b0;
    for(int i = 0; i < NUM_ENTRYS; i++) begin
      if(~entries[i].occupied) begin 
        entry_open = 1'b1;
        entry_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].address == {paddr[PADDR_W-1:$clog2(BLOCK_SIZE)], {($clog2(BLOCK_SIZE)){1'b0}}}) begin
        match_made = 1'b1;
        match_index = ($clog2(NUM_ENTRYS))'(i);
      end

      // Used to set the drain index
      if(entries[i].occupied && entries[i].address == {l2_paddr[PADDR_W-1:$clog2(BLOCK_SIZE)], {($clog2(BLOCK_SIZE)){1'b0}}}) begin
        l2_match_made = 1'b1;
        l2_match_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].should_drain && ($clog2(NUM_ENTRYS))'(i) != drain_index) begin
        theorized_drain_index = ($clog2(NUM_ENTRYS))'(i);
        theorized_drain_index_valid = 1'b1;
      end
    end

    if(l2_completed && ~draining) begin
      wanted_drain_index = l2_match_index;
    end else if(draining && (entries[drain_index].count == 0)) begin
      wanted_drain_index = theorized_drain_index;
    end
  end

  assign id_out = entries[drain_index].queue[entries[drain_index].head].id;
  assign write_out = entries[drain_index].queue[entries[drain_index].head].store_val;
  assign offset_out = entries[drain_index].queue[entries[drain_index].head].block_offset;
  assign output_valid = draining;
  assign is_store_out = entries[drain_index].queue[entries[drain_index].head].is_store;

  always_ff @(posedge clk) begin
    // Handle match or open cases
    // Don't fill entry if l2 is done
    if(l2_completed) begin
      // Force the mshr into drain mode or update the next entry to drain
      if(~draining) begin 
        draining <= 1'b1;
        drain_index <= wanted_drain_index;
      end
      entries[l2_match_index].should_drain <= 1'b1;
    end 

    // TODO Have ready out for l2 and block it

    if(miss && valid) begin
      if(match_made) begin  // Secondary miss
        entries[match_index].queue[entries[match_index].tail].is_store <= is_store;
        entries[match_index].queue[entries[match_index].tail].id <= id_in;
        entries[match_index].queue[entries[match_index].tail].block_offset <= paddr[$clog2(BLOCK_SIZE)-1:0];
        entries[match_index].queue[entries[match_index].tail].store_val <= store_data;
        entries[match_index].tail <= entries[match_index].tail + 1;
        entries[match_index].count <= entries[match_index].count + 1;
      end else if(entry_open) begin // Primary miss
        entries[entry_index].queue[0].is_store <= is_store;
        entries[entry_index].queue[0].id <= id_in;
        entries[entry_index].queue[0].block_offset <= paddr[$clog2(BLOCK_SIZE)-1:0];
        entries[entry_index].queue[0].store_val <= store_data;
        entries[entry_index].address <= {paddr[PADDR_W-1:$clog2(BLOCK_SIZE)], {($clog2(BLOCK_SIZE)){1'b0}}};
        entries[entry_index].occupied <= 1'b1;
        entries[entry_index].head <= 0;
        entries[entry_index].tail <= 1;
        entries[entry_index].count <= 1;
      end else begin  // Stall
      end
    end

    if(draining) begin
      if(entries[drain_index].count == 1) begin
        if(theorized_drain_index_valid) begin
          drain_index <= theorized_drain_index;
        end else begin
          draining <= 1'b0;
        end
        entries[drain_index].should_drain <= 1'b0;
        entries[drain_index].occupied <= 1'b0;
      end 

      entries[drain_index].head <= entries[drain_index].head + 1;
      entries[drain_index].count <= entries[drain_index].count - 1;
    end
  end

endmodule

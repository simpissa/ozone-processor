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
  input logic[VADDR_W-1:0] vaddr,
  input logic loadValid,
  input logic[ID_LENGTH-1:0] load_id,
  input logic[ID_LENGTH-1:0] store_id,
  input logic storeValid,
  input logic[63:0] store_data,
  output logic[ID_LENGTH-1:0] load_id_completed,
  output logic[ID_LENGTH-1:0] store_id_completed,

  output logic l1ready,
  output logic miss_result,
  output logic[63:0] data_out,
  output logic data_valid,
  // l2 params
  input logic[BLOCK_SIZE*8-1:0] l2_data_in,
  input logic l2_data_valid,
  input logic[PADDR_W-1:0] l2_paddr,
  // tlb params
  input logic[PADDR_W-1:0] tlb_paddr_in,
  input logic tlb_paddr_ready,
  output logic[VADDR_W-1:0] tlb_vaddr_out,
  output logic tlb_vaddr_valid
);

  localparam int NUM_SETS = CAPACITY / BLOCK_SIZE / NUM_WAYS;
  localparam int TAG_SIZE = PADDR_W-($clog2(NUM_SETS) + $clog2(BLOCK_SIZE));

  typedef struct packed {
    logic [NUM_WAYS-1:0][BLOCK_SIZE*8-1:0] data;
  } data_arr_set;

  typedef struct packed {
    logic [NUM_WAYS-1:0][TAG_SIZE-1:0] data;
    logic valid;
    logic lru;
    logic dirty;
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
  } stage3_info;

  data_arr_set data_arr[NUM_SETS-1:0];
  tag_arr_set tag_arr[NUM_SETS-1:0];

  data_arr_set stage1_data_set;
  tag_arr_set stage1_tag_set;
  data_arr_set stage2_data_set;
  tag_arr_set stage2_tag_set;

  logic stage2_blocked, stage3_blocked;

  stage2_info stage2;
  stage3_info stage3;

  // TODO SET ALL TO DEFAULT
  initial begin 

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

  // TODO Decide if pipeline stays valid or invalid during blockage
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
    end else begin
      stage2.valid <= 1'b0;
    end
  end

  /*
  / Stage 2
  */
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
          data_sel = stage2.data_set.data[i][BLOCK_SIZE * 8 * stage2.block_offset +: 64];
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
    end else begin
      stage3.valid <= 1'b0;
    end
  end

  logic should_stall_mshr;  // mshr full or busy
  logic[ID_LENGTH-1:0] mshr_store_id; // id for instruciton being fulfilled
  logic[ID_LENGTH-1:0] mshr_load_id;
  logic mshr_store_valid; // If outputs are valid
  logic mshr_load_valid;
  logic[63:0] mshr_data_out; // store output

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
          .id_in(), //TODO take id
          .miss(stage3.miss),
          .valid(stage3.valid),
          .l2_completed(l2_data_valid),
          .l2_paddr(l2_paddr),
          .is_store(stage3.is_store),
          .stall(should_stall_mshr),
          .store_id_out(mshr_store_id),
          .load_id_out(mshr_load_id),
          .write_out(mshr_data_out),
          .load_valid(mshr_load_valid),
          .store_valid(mshr_store_valid)
        );

  assign miss_result = stage3.miss;

  // logic 

  always_comb begin
    data_valid = 1'b0;
    data_out = stage3.data;
    if(l2_data_valid) begin
      // pop mshrs and update cache or send data
      data_out = l2_data_in[stage3.block_offset * 8 +:64];
    end else if(stage3.miss & stage3.valid) begin 
      // push into mshr and send out to l2
      // Stall if mshr queue is full
    end else if(stage3.valid) begin 
      // update cache or send out data
      if(stage3.is_store) begin
        // Update cache
      end else begin
        data_valid = 1'b1;
      end
    end
  end
  
  // Update on a store
  always_ff @(posedge clk) begin
    // Update cache with normal state if not updating with l2
    // l2 should take priority with updating if on a miss, use mshr to determine
    if(~l2_data_valid & stage3.valid & ~stage3.miss & ~l2_data_valid & stage3.is_store) begin
        data_arr[stage3.set_index].data[stage3.way_store_index][stage3.block_offset*8+:64] <= stage3.store_data;
    end
  end
endmodule

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
  output logic[ID_SIZE-1:0] store_id_out,
  output logic[ID_SIZE-1:0] load_id_out,
  output logic[DATA_SIZE-1:0] write_out,
  output logic load_valid,
  output logic store_valid
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
    logic[$clog2(QUEUE_SIZE)-1:0] count;
  } mshr_entry;

  mshr_entry[NUM_ENTRYS-1:0] entries;

  logic entry_open;
  logic[$clog2(NUM_ENTRYS)-1:0] entry_index;
  logic match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] match_index;
  logic l2_match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] l2_match_index;

  logic draining;

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
    for(int i = 0; i < NUM_ENTRYS; i++) begin
      if(~entries[i].occupied) begin 
        entry_open = 1'b1;
        entry_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].address == {paddr[PADDR_W-1:$clog2(BLOCK_SIZE)], {($clog2(BLOCK_SIZE)){1'b0}}}) begin
        match_made = 1'b1;
        match_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].address == {l2_paddr[PADDR_W-1:$clog2(BLOCK_SIZE)], {($clog2(BLOCK_SIZE)){1'b0}}}) begin
        l2_match_made = 1'b1;
        l2_match_index = ($clog2(NUM_ENTRYS))'(i);
      end
    end

    load_valid = ~entries[match_index].queue[entries[match_index].head].is_store & draining;
    store_valid = entries[match_index].queue[entries[match_index].head].is_store & draining;

    // Drain if l2 is done, stop draining when queue empty
    // TODO Commented out to compile but need to have a drain state 
    // for the entrys that begin clearing out the entrys. Since we only
    // have one output port id assume we only have 1 global drain state
    // draining = draining;
    // if(l2_completed) begin
    //   draining = 1'b1;
    // end else if(draining && (entries[l2_match_index].count == 0)) begin

    // end
  end

  always_ff @(posedge clk) begin
    // Handle match or open cases
    // Don't fill entry if l2 is done
    if(l2_completed) begin
      // Clear queues until head==tail
      // Need to differentiate between when the queue is empty and full
      // Assume  match made, might have to add error checking later if it causes issues
      // technically no clearing has to be done just move head
      entries[l2_match_index].head <= entries[l2_match_index].head + 1;
      entries[l2_match_index].count <= entries[l2_match_index].count - 1;
    end else if(miss && valid) begin
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
      end else begin  // Stall
      end
    end
  end

endmodule

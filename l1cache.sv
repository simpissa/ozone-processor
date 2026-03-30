`timescale 1ns / 1ps

module l1cache #(
	parameter int VADDR_W = 48,
  parameter int PADDR_W = 30,
  parameter int BLOCK_SIZE = 64,
  parameter int NUM_WAYS = 2,
  parameter int CAPACITY = 512,
  parameter int NUM_MSHRS = 2,
  parameter int MSHR_QUEUE_SIZE = 4,
  parameter int ID_LENGTH = 4
)(
	input  logic         clk,
	input  logic         reset,
  // sq params
  input logic [VADDR_W-1:0] store_vaddr,
  input logic [ID_LENGTH-1:0] store_id,
  input logic storeValid,
  input logic [63:0] store_data,
  output logic store_received,
  output logic [ID_LENGTH-1:0] store_id_completed,
  output logic store_finished,

  // lq params
  input logic loadValid,
  input logic [VADDR_W-1:0] load_vaddr,
  input logic [ID_LENGTH-1:0] load_id,
  output logic load_received,
  // TODO: is load_finished the same as data_valid? if so, remove one 
  output logic load_finished,
  output logic [ID_LENGTH-1:0] load_id_completed,
  output logic [63:0] data_out,
  output logic data_valid,
  
  // relevant to both lq and sq
  output logic l1ready,

  // Query L2
  output logic l2_req_valid, // our request is valid
  output logic l2_req_rw, // read/write operation associated with request (not sure which is which, needs to be worked out w/ l2)
  output logic [PADDR_W-$clog2(BLOCK_SIZE)-1:0] l2_req_paddr, // physical addr associated w/ request
  output logic [BLOCK_SIZE*8-1:0] l2_req_data, // data for write request
  output logic [ID_LENGTH-1:0] l2_query_id, // id on request
  // output logic [BLOCK_SIZE*8-1:0] l2_evict_data,
  // output logic l2_evict_valid, 
  input logic l2_ready_for_req, // is l2 ready for request

  // L2 Response
  input logic l2_resp_valid,
  input logic [BLOCK_SIZE*8-1:0] l2_resp_data,
  input logic [PADDR_W-$clog2(BLOCK_SIZE)-1:0] l2_paddr,

  // tlb params
  input logic [PADDR_W-1:0] tlb_paddr_in,
  input logic tlb_paddr_ready,
  output logic [VADDR_W-1:0] tlb_vaddr_out,
  output logic tlb_vaddr_valid
);

  localparam int NUM_SETS = CAPACITY / BLOCK_SIZE / NUM_WAYS;
  localparam int TAG_SIZE = PADDR_W-($clog2(NUM_SETS) + $clog2(BLOCK_SIZE));

  //  verbose debug mode
  logic DBG;

  typedef struct packed {
    logic [NUM_WAYS-1:0][BLOCK_SIZE*8-1:0] data;
  } data_arr_set;

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

  data_arr_set[NUM_SETS-1:0] data_arr;
  tag_arr_set[NUM_SETS-1:0] tag_arr;

  task print_cache;
    $display("<------------------------------------ INTERNAL CACHE STATE ------------------------------------->\n");
    $display("|-----------------------------------------------------------------------------------------------|");
    $write("| SET ");
    for (int i = 0; i < NUM_WAYS; ++i) begin
      $write("| %1s | %1s | %3s | %-7s | %-18s ", "V", "D", "LRU", "Tag", "Data");
    end
    $display("|");
    $display("|-----------------------------------------------------------------------------------------------|");
    for (int i = 0; i < NUM_SETS; ++i) begin
        $write("| %3d ", i);
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
    $display("|-----------------------------------------------------------------------------------------------|");

    $display("\nStage 2 Info: valid %b store %b set %d vaddr %012x", stage2.valid, stage2.is_store, 
                    stage2.set_index, stage2.vaddr);

    $display("Stage 3 Info: valid %b store %b set idx %d way idx %d miss %b paddr %08x\n", stage3.valid,
                    stage3.is_store, stage3.set_index, stage3.way_store_index, stage3.miss, stage3.paddr);
        
  endtask

  logic stage2_blocked, stage3_blocked;
  logic l2_full_block, mshr_full_block;

  stage2_info stage2;
  stage3_info stage3;

  // TODO SET ALL TO DEFAULT
  initial begin 
    
    if (!$value$plusargs("L1DEBUG=%b", DBG)) begin
        DBG = 0;
    end

    data_arr = 0;
    tag_arr = 0;
    stage2 = 0;
    stage3 = 0;

    // if (DBG)
    //     print_cache();
  end

  always @(posedge clk) begin
    if (reset) begin
      if (DBG)
          $display("Resetting internal cache state...");
      data_arr <= '0;
      tag_arr <= '0;
      stage2 <= '0;
      stage3 <= '0;
    end

    // if (DBG)
    //     print_cache();
  end

  /**
  / Stage 1
  */
  logic is_valid;
  assign is_valid = storeValid | loadValid;
  logic[$clog2(BLOCK_SIZE)-1:0] block_offset;
  logic[$clog2(NUM_SETS)-1:0] set_index;
    
    // TODO: changed this to always @ because it seemed it was running much more than necessary
    // will this work it does it need to go back? 

  always_comb begin
    l1ready = 1'b0;
    tlb_vaddr_valid = 1'b0;
    load_received = 0;
    store_received = 0;

    // if (DBG)
    //     $write("L1 Status: Checking load/store req valid. ");
    
    tlb_vaddr_out = '0;

    if (DBG) begin
      $display("st2 blocked: %b st3 blocked: %b", stage2_blocked, stage3_blocked);
    end

    // used to be ~stage3_blocked & below, but stage2_blocked is 1 if stage3 is blocked, so i think its 
    // redundant
    if(~stage2_blocked) begin
      l1ready = 1'b1;
      tlb_vaddr_valid = is_valid;
      if(storeValid) begin
          tlb_vaddr_out = store_vaddr;
          store_received = 1;
          // if (DBG)
          //     $write("Received store request");

      end else if(loadValid) begin
          tlb_vaddr_out = load_vaddr;
          load_received = 1;
          // if (DBG)
          //     $write("Received load request");
      end
    end

    // if (DBG)
    //     $display();
  end

  assign block_offset = tlb_vaddr_out[$clog2(BLOCK_SIZE)-1:0];
  assign set_index = tlb_vaddr_out[$clog2(BLOCK_SIZE)+$clog2(NUM_SETS)-1:$clog2(BLOCK_SIZE)];

  /*
  / Stage 2 Pipeline
  */
  always_ff @(posedge clk) begin
    if(~stage3_blocked && ~stage2_blocked) begin

        // if (DBG)
        //     $display("\nL1 Status: Propagating request data into stage II.");

      stage2.data_set <= data_arr[set_index];
      stage2.tag_set <= tag_arr[set_index];
      stage2.set_index <= set_index;
      stage2.block_offset <= block_offset;
      stage2.vaddr <= tlb_vaddr_out;
      stage2.store_data <= store_data;
      stage2.valid <= is_valid;
      stage2.is_store <= storeValid;
      if(storeValid) begin
        stage2.instr_id <= store_id;
      end else begin
        stage2.instr_id <= load_id;
      end

      // if (DBG)
      //   $display("valid: %b set: %d offset: %d vaddr: %012h str data: %016x is_store: %b id: %d",
      //           is_valid,
      //           set_index,
      //           block_offset,
      //           tlb_vaddr_out,
      //           store_data,
      //           storeValid,
      //           storeValid ? store_id : load_id); 

    end else begin
      // stage2.valid <= 1'b0;
    end
  end

  /*
  / Stage 2 Select data and tag to be passed onto the next stage
  */
  logic[TAG_SIZE-1:0] paddr_tag;
  logic[NUM_WAYS-1:0] tag_comps;
  logic[TAG_SIZE-1:0] tag_sel;
  logic[63:0] data_sel;
  logic[$clog2(NUM_WAYS)-1:0] way_index;
  logic miss;

  assign paddr_tag = tlb_paddr_in[PADDR_W-1:$clog2(NUM_SETS) + $clog2(BLOCK_SIZE)];
  assign stage2_blocked = (~tlb_paddr_ready & stage2.valid) | stage3_blocked;

  always_comb begin
    if(DBG) 
      $display("TLB_ADDR %x, TLB_ADDR_IN_V %b, stage3_C_V %b, stage3_V %b, stage2_V %b, stage1_V %b ", tlb_paddr_in, tlb_paddr_ready, stage3_curr_valid, stage3.valid, stage2.valid, is_valid);
    miss = 1'b1;
    tag_comps = 0;
    tag_sel = 0;
    data_sel = 0;
    way_index = 0;
    if(~stage2_blocked) begin
      for(int i = 0; i < NUM_WAYS; i++) begin
        tag_comps[i] = stage2.tag_set.valid[i] & (stage2.tag_set.data[i] == paddr_tag);
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
    if((~stage2_blocked) & (~stage3_blocked)) begin
        // if (DBG) begin
        //     $display("\nL1 Status: Propagating stage II values & data/tag values into stage III.");
        //     $display("valid %b data %016x tag %05x vaddr %012x str data %016x miss %b paddr %08x",
        //             stage2.valid,
        //             data_sel,
        //             paddr_tag,
        //             stage2.vaddr,
        //             stage2.store_data,
        //             miss,
        //             tlb_paddr_in);
        //     $display("is_store %b way idx %b set idx %d offs %d id %d",
        //             stage2.is_store,
        //             way_index,
        //             stage2.set_index,
        //             stage2.block_offset,
        //             stage2.instr_id);
        // end
            
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
      // stage3.valid <= 1'b0;
    end
  end

  logic mshr_should_stall;  // mshr full or busy
  logic[ID_LENGTH-1:0] mshr_id; // id for instruciton being fulfilled
  logic mshr_out_valid; // If outputs are valid
  logic mshr_is_store_out;
  logic mshr_should_inform_l2; // Tell the mshr to inform l2 about request once it is available again
  logic mshr_l2_req_valid;
  logic[ID_LENGTH-1:0] mshr_l2_req_id;
  logic[PADDR_W-$clog2(BLOCK_SIZE)-1:0] mshr_l2_req_paddr;
  logic mshr_l2_req_is_store;
  logic[63:0] mshr_data_out; // store output
  logic[$clog2(BLOCK_SIZE)-1:0] mshr_offset; // Corresponding block offset
  logic[$clog2(NUM_SETS)-1:0] mshr_set;
  logic[$clog2(NUM_WAYS)-1:0] mshr_way;

  mshr #(.NUM_ENTRYS(NUM_MSHRS),
        .QUEUE_SIZE(MSHR_QUEUE_SIZE),
        .PADDR_W(PADDR_W),
        .DATA_SIZE(64),
        .ID_SIZE(ID_LENGTH),
        .OFFSET_SIZE($clog2(BLOCK_SIZE)),
        .BLOCK_SIZE(BLOCK_SIZE),
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS)) mshr_module(
          .clk(clk),
          .reset(reset),
          .store_data(stage3.store_data),
          .paddr(stage3.paddr),
          .id_in(stage3.instr_id),
          .should_inform_l2(mshr_should_inform_l2),
          .is_l2_ready(l2_ready_for_req),
          .miss(stage3.miss),
          .valid(stage3.valid),
          .l2_completed(l2_resp_valid),
          .l2_paddr(l2_paddr),
          .l2_way_stored(way_evicted),
          .is_store(stage3.is_store),
          .stall(mshr_should_stall),
          .id_out(mshr_id),
          .write_out(mshr_data_out),
          .output_valid(mshr_out_valid),
          .offset_out(mshr_offset),
          .set_out(mshr_set),
          .way_out(mshr_way),
          .is_store_out(mshr_is_store_out),
          .l2_req_valid(mshr_l2_req_valid),
          .l2_req_id(mshr_l2_req_id),
          .l2_req_paddr(mshr_l2_req_paddr),
          .l2_req_is_store(mshr_l2_req_is_store)
        );

  logic [63:0] load_data_out;
  logic [ID_LENGTH-1:0] id_instr_completed;
  logic instr_complete_is_store;
  logic stage3_curr_valid;

  always_comb begin
    store_finished = 1'b0;
    load_finished = 1'b0;
    data_out = stage3.data;
    data_valid = 1'b0;
    l2_req_valid = 1'b0;
    load_id_completed = '0;
    store_id_completed = '0;

    l2_req_paddr = '0;
    l2_req_data = '0;
    l2_query_id = '0;
    l2_req_rw = 1'b0;
    
    stage3_curr_valid = stage3.valid;
    // Tells the mshr that this entry should look out for when l2 can take a request
    mshr_should_inform_l2 = ~l2_ready_for_req & stage3.valid & stage3_curr_valid & stage3.miss;

    l2_full_block = (mshr_l2_req_valid &  ~(stage3.paddr[PADDR_W-1:$clog2(BLOCK_SIZE)] == mshr_l2_req_paddr) & stage3.valid & stage3.miss);
    mshr_full_block = mshr_out_valid | mshr_should_stall;
    
    stage3_blocked = mshr_full_block | l2_full_block;
    // $display("MSHR Stall: %b, MSHR_V: %b, MSHR_REQ_V: %b, MSHR_REQ_ADDR: %x", mshr_should_stall, mshr_out_valid, mshr_l2_req_valid, mshr_l2_req_paddr);
    if(mshr_out_valid) begin
      stage3_blocked = 1'b1;
      if(mshr_is_store_out) begin
        // Store here if we want to dispense entire queue here
        store_finished = 1'b1;
        store_id_completed = mshr_id;
      end else begin
        // Output load here, loads must be done one at a time since their pins need output
        load_finished = 1'b1;
        data_out = data_arr[mshr_set].data[mshr_way][8*mshr_offset +: 64];
        load_id_completed = mshr_id;
      end
    end else if(stage3.valid & ~stage3.miss) begin 
      // Output hit
      if(~stage3.is_store) begin
        // Presumably only handle loads since stores are handled in ff
        load_finished = 1'b1;
        data_out = stage3.data;
        load_id_completed = stage3.instr_id;
      end else begin
        store_finished = 1'b1;
        store_id_completed = stage3.instr_id;
      end
    end 

    // Output line if dirty to update l2
    if(l2_resp_valid & tag_arr[l2_paddr_set].valid[way_evicted] & tag_arr[l2_paddr_set].dirty[way_evicted]) begin
      l2_req_valid = 1'b1;
      l2_req_rw = 1'b1;
      l2_req_data = data_arr[l2_paddr_set].data[way_evicted];
    end else if(mshr_l2_req_valid) begin 
      // MSHR modules auto handle the miss, l2 should be sent required miss data
      l2_req_valid = 1'b1;
      l2_req_paddr = mshr_l2_req_paddr;
      l2_query_id = mshr_l2_req_id;
      // $display("OUTPUTTING TO L2 THROUGH MSHR");
    end else if(stage3.valid & l2_ready_for_req) begin 
      // MSHR modules auto handle the miss, l2 should be sent required miss data
      l2_req_valid = 1'b1;
      l2_req_paddr = stage3.paddr[PADDR_W-1:$clog2(BLOCK_SIZE)];
      l2_query_id = stage3.instr_id;
      // $display("OUTPUTTING TO L2 THROUGH PIPE");
    end else begin
      // Presumably output invalid
      // if(stage3.valid)
        // $display("Miss in stage 3 but l2 full, move to mshr");
    end

    data_valid = load_finished;
  end

  logic[$clog2(NUM_SETS)-1:0] l2_paddr_set = l2_paddr[$clog2(NUM_SETS)-1:0];
  logic[$clog2(NUM_WAYS)-1:0] way_evicted = tag_arr[l2_paddr_set].lru;
  logic[TAG_SIZE-1:0] l2_paddr_tag = l2_paddr[$clog2(NUM_SETS) +: TAG_SIZE];
  
  // Update on a store
  always_ff @(posedge clk) begin
    // Update cache with normal state if not updating with l2
    // l2 should take priority with updating if on a miss, use mshr to determine
    if(mshr_out_valid & mshr_is_store_out) begin
      data_arr[mshr_set].data[mshr_way][mshr_offset*8 +: 64] <= mshr_data_out;
    end else if(l2_resp_valid) begin
      // Bring in the data into the cache, have seperate logic for outputting instrs
      // from mshr
      // lru way 0, evict and make 1 lru
      if(way_evicted == 1'b0) begin
        tag_arr[l2_paddr_set].lru <= 1'b1;
      end else begin        
        tag_arr[l2_paddr_set].lru <= 1'b0;
      end
      // Store l2 data in cache and set to clean and valid
      data_arr[l2_paddr_set].data[way_evicted] <= l2_resp_data;
      tag_arr[l2_paddr_set].data[way_evicted] <= l2_paddr_tag;
      tag_arr[l2_paddr_set].dirty[way_evicted] <= 1'b0;
      tag_arr[l2_paddr_set].valid[way_evicted] <= 1'b1;
    end else if(stage3.valid & ~stage3.miss) begin
      if(stage3.is_store) begin
          data_arr[stage3.set_index].data[stage3.way_store_index][stage3.block_offset*8+:64] <= stage3.store_data;
          tag_arr[stage3.set_index].dirty[stage3.way_store_index] <= 1'b1;
      end
        tag_arr[stage3.set_index].lru <= ~tag_arr[stage3.set_index].lru;
    end
  end
endmodule

// TODO MSHR Should feed loads forward if same offset
// TODO IF L2 CANT HANDLE BOTH AT SAME TIME, ADD DELAY TO OUTPUT
module mshr#(
  parameter int NUM_ENTRYS = 2,
	parameter int QUEUE_SIZE = 4,
  parameter int PADDR_W = 30,
  parameter int DATA_SIZE = 64,
  parameter int ID_SIZE = 3,
  parameter int OFFSET_SIZE = 6,
  parameter int BLOCK_SIZE = 64,
  parameter int NUM_WAYS = 2,
  parameter int NUM_SETS = 4
)(
  input logic clk,
  input logic reset,
  input logic[DATA_SIZE-1:0] store_data,
  input logic[PADDR_W-1:0] paddr,
  input logic[ID_SIZE-1:0] id_in,
  input logic should_inform_l2,
  input logic is_l2_ready,
  input logic miss,
  input logic valid,
  input logic l2_completed,
  input logic[PADDR_W-$clog2(BLOCK_SIZE)-1:0] l2_paddr,
  input logic[$clog2(NUM_WAYS)-1:0] l2_way_stored,
  input logic is_store,

  output logic stall,
  output logic[ID_SIZE-1:0] id_out,
  output logic[DATA_SIZE-1:0] write_out,
  output logic[OFFSET_SIZE-1:0] offset_out,
  output logic[$clog2(NUM_SETS)-1:0] set_out,
  output logic[$clog2(NUM_WAYS)-1:0] way_out,
  output logic output_valid,
  output logic is_store_out,
  output logic[ID_SIZE-1:0] l2_req_id,
  output logic[PADDR_W-$clog2(BLOCK_SIZE)-1:0] l2_req_paddr,
  output logic l2_req_valid,
  output logic l2_req_is_store
);

  typedef struct packed {
    logic is_store;
    logic[ID_SIZE-1:0] id; // instruciton id
    logic[OFFSET_SIZE-1:0] block_offset;
    logic[DATA_SIZE-1:0] store_val;
  } queue_entry;

  typedef struct packed {
    queue_entry[QUEUE_SIZE-1:0] queue;
    logic[PADDR_W-$clog2(BLOCK_SIZE)-1:0] address;
    logic occupied;
    logic[$clog2(QUEUE_SIZE)-1:0] head;
    logic[$clog2(QUEUE_SIZE)-1:0] tail;
    logic[$clog2(QUEUE_SIZE):0] count;
    logic[$clog2(NUM_WAYS)-1:0] way_selected;
    logic should_drain;
    logic should_inform_l2;
  } mshr_entry;

  mshr_entry[NUM_ENTRYS-1:0] entries;
  logic[$clog2(NUM_ENTRYS):0] num_entries_taken;

  logic entry_open;
  logic[$clog2(NUM_ENTRYS)-1:0] entry_index;
  logic match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] match_index;
  logic l2_match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] l2_match_index;
  logic l2_pending_match_made;
  logic[$clog2(NUM_ENTRYS)-1:0] l2_pending_match_index;

  // Global draining and drain entry index
  logic draining;
  logic[$clog2(NUM_ENTRYS)-1:0] drain_index;
  logic[$clog2(NUM_ENTRYS)-1:0] wanted_drain_index;
  logic[$clog2(NUM_ENTRYS)-1:0] theorized_drain_index;
  logic theorized_drain_index_valid;

  initial begin 
    entries = 0;
    num_entries_taken = 0;
    draining = 0;
  end

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
    l2_pending_match_made = 1'b0;
    l2_pending_match_index = 0;
    for(int i = 0; i < NUM_ENTRYS; i++) begin
      if(~entries[i].occupied) begin 
        entry_open = 1'b1;
        entry_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].address == paddr[PADDR_W-1:$clog2(BLOCK_SIZE)]) begin
        match_made = 1'b1;
        match_index = ($clog2(NUM_ENTRYS))'(i);
      end

      // Used to set the drain index
      if(entries[i].occupied && entries[i].address == l2_paddr[PADDR_W-$clog2(BLOCK_SIZE)-1:0]) begin
        l2_match_made = 1'b1;
        l2_match_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].should_drain && ($clog2(NUM_ENTRYS))'(i) != drain_index) begin
        theorized_drain_index_valid = 1'b1;
        theorized_drain_index = ($clog2(NUM_ENTRYS))'(i);
      end

      if(entries[i].occupied && entries[i].should_inform_l2) begin
        l2_pending_match_made = 1'b1;
        l2_pending_match_index = ($clog2(NUM_ENTRYS))'(i);
      end
    end

    if(l2_completed && ~draining) begin
      wanted_drain_index = l2_match_index;
    end else if(draining && (entries[drain_index].count == 0)) begin
      wanted_drain_index = theorized_drain_index;
    end
  end
  
  // Stall if we should be draining or if we are full and have another miss
  assign stall = draining | 
                (miss & valid & (~match_made) & (num_entries_taken == ($clog2(NUM_ENTRYS)+1)'(NUM_ENTRYS))) | 
                (miss & valid & match_made & (entries[match_index].count == ($clog2(QUEUE_SIZE)+1)'(QUEUE_SIZE)));

  assign id_out = entries[drain_index].queue[entries[drain_index].head].id;
  assign write_out = entries[drain_index].queue[entries[drain_index].head].store_val;
  assign offset_out = entries[drain_index].queue[entries[drain_index].head].block_offset;
  assign set_out = entries[drain_index].address[$clog2(NUM_SETS)-1:0];
  assign way_out = entries[drain_index].way_selected;
  assign output_valid = draining;
  assign is_store_out = entries[drain_index].queue[entries[drain_index].head].is_store;

  assign l2_req_id = entries[l2_pending_match_index].queue[entries[l2_pending_match_index].head].id;
  assign l2_req_paddr = entries[l2_pending_match_index].address;
  assign l2_req_valid = entries[l2_pending_match_index].should_inform_l2 & is_l2_ready;
  assign l2_req_is_store = entries[l2_pending_match_index].queue[entries[l2_pending_match_index].head].is_store;

  always_ff @(posedge clk) begin
    if(reset) begin
      draining <= 0;
      drain_index <= 0;
      entries <= 0;
      num_entries_taken <= 0;
    end else begin
      // Handle match or open cases
      // Don't fill entry if l2 is done
      if(l2_completed) begin
        // Force the mshr into drain mode or update the next entry to drain
        if(~draining) begin 
          draining <= 1'b1;
          drain_index <= wanted_drain_index;
        end
        entries[l2_match_index].should_drain <= 1'b1;
        entries[l2_match_index].way_selected <= l2_way_stored;
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
          entries[entry_index].address <= paddr[PADDR_W-1:$clog2(BLOCK_SIZE)];
          entries[entry_index].occupied <= 1'b1;
          num_entries_taken <= num_entries_taken + 1;
          entries[entry_index].head <= 0;
          entries[entry_index].tail <= 1;
          entries[entry_index].count <= 1;
          entries[entry_index].should_inform_l2 <= ~is_l2_ready;
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
          num_entries_taken <= num_entries_taken - 1;
        end 

        entries[drain_index].head <= entries[drain_index].head + 1;
        entries[drain_index].count <= entries[drain_index].count - 1;
      end

      if(is_l2_ready && l2_pending_match_made) begin
        entries[l2_pending_match_index].should_inform_l2 <= 1'b0;
      end
    end
  end

endmodule

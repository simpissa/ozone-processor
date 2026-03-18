module l1cache #(
  parameter int VADDR_W = 48,
  parameter int PADDR_W = 30,
  parameter int BLOCK_SIZE = 64,
  parameter int NUM_WAYS = 2,
  parameter int CAPACITY = 512
)(
	input  logic         clk,
	input  logic         reset,
  // lsq params
  input logic[VADDR_W-1:0] v_addr,
  input logic loadValid,
  input logic storeValid,

  output logic l1ready,
  output logic miss,
  output logic[63:0] data_out,
  // l2 params
  input logic[BLOCK_SIZE*8-1:0] l2_data_in,
  // tlb params
  input logic[PADDR_W-1:0] tlb_paddr_in,
  input logic tlb_paddr_ready,
  output logic[VADDR_W-1:0] tlb_vaddr_out,
  output logic tlb_vaddr_valid
);

  // Total data: 
  // BLOCK_SIZE * WAYS * SETS
  // Sets = CAPACITY / BLOCK_SIZE / WAYS
  typedef struct packed {
    logic [NUM_WAYS-1:0][BLOCK_SIZE*8-1:0] data;
    logic lru;
  } data_arr_set;

  typedef struct packed {
    logic [NUM_WAYS-1:0][PADDR_W-$clog2(CAPACITY)-1:0] data;
    logic lru;
  } tag_arr_set;

  logic[$clog2(CAPACITY)-1:0] cache_index_bits;
  logic[$clog2(BLOCK_SIZE)-1:0] block_offset;
  logic[$clog2(CAPACITY)-$clog2(BLOCK_SIZE)-1:0] set_index;
  logic[VADDR_W-$clog2(CAPACITY)-1:0] virtual_page_num;

  data_arr_set data_arr[CAPACITY/BLOCK_SIZE/NUM_WAYS-1:0];
  tag_arr_set tag_arr[CAPACITY/BLOCK_SIZE/NUM_WAYS-1:0];

  data_arr_set stage1_data_set;
  tag_arr_set stage1_tag_set;
  data_arr_set stage2_data_set;
  tag_arr_set stage2_tag_set;

  logic stage1_type; // 0 load 1 store
  logic stage2_type;
  
  // TODO needed to add this to compile, you should make sure its right
  // the width is especially not correct, given that its hard coded
  logic [20:0] stage2_paddr_tag;
  logic[PADDR_W-1:0] stage2_tlb_paddr;
  logic[PADDR_W*NUM_WAYS-1:0] stage2_tlb_paddr_expanded;
  logic[NUM_WAYS-1:0] stage2_tag_comps;

  logic stage3_blocked;

  assign stage3_blocked = 1'b0;


  always_ff @(posedge clk) begin

    if(reset) begin
      data_arr <= '{default: 0};
      tag_arr <= '{default: 0};
      stage1_data_set <= 0;
      stage1_tag_set <= 0;
      stage2_data_set <= 0;
      stage2_tag_set <= 0;
      tlb_vaddr_valid <= 0;
      stage2_tlb_paddr <= 0;
      stage2_tag_comps <= 0;
    end else begin
      /*
      / Pipeline stage 1
      / Read address, decode, and send to tlb
      / ACCESS THE ARRAYS HERE SEND DATA DOWN THE PIPE
      */
      if(~stage3_blocked) begin
        // Get index bits corresponding to cache blocks
        cache_index_bits = v_addr[$clog2(CAPACITY)-1:0];

        block_offset = cache_index_bits[$clog2(BLOCK_SIZE)-1:0];
        set_index = cache_index_bits[$clog2(CAPACITY)-1:$clog2(BLOCK_SIZE)]; 

        // TODO fix this, gave an error that it needs 2 bit index not 3, but the way i am fixing it is most certainly incorrect
        stage1_data_set <= data_arr[set_index[1:0]];
        stage1_tag_set <= tag_arr[set_index[1:0]];


        // Send virtual page number to tlb (send whole addr for now)
        virtual_page_num = v_addr[VADDR_W-1:$clog2(CAPACITY)];
        tlb_vaddr_out <= v_addr;
        tlb_vaddr_valid <= 1;

        if(storeValid) begin
          stage1_type <= 1;
        end else if(loadValid) begin
          stage1_type <=0;
        end
      end else begin
        tlb_vaddr_valid <= 0;
      end

      /*
      / Pipeline stage 2
      / Get tlb address and compare to select
      */
      if(tlb_paddr_ready & ~stage3_blocked) begin
        // Move over data into next part of pipeline
        stage2_data_set <= stage1_data_set;
        stage2_tag_set <= stage1_tag_set;
        stage2_type = stage1_type;

        // In between movements for tag matching
        stage2_tlb_paddr <= tlb_paddr_in;
        stage2_paddr_tag = tlb_paddr_in[PADDR_W-1:$clog2(CAPACITY)];

        for(int i = 0; i < NUM_WAYS; i++) begin
          stage2_tag_comps[i] <= &(stage1_tag_set.data[i] == stage2_paddr_tag);
        end

      end 

      /*
      / Pipeline Stage 3
      / Output values or report misses
      / will stall if mshr's queues full
      */

      // Miss
      if(stage2_tag_comps == 0) begin
        miss <= 1'b1;
      end else begin
        miss <= 1'b0;
        if(stage2_type == 0) begin
          data_out <= stage2_data_set.data[stage2_tag_comps][63:0];
        end else begin
          // data_arr[] <=
        end
      end

    end



  end

endmodule

// module lru(

// );

// endmodule

module mshr#(
	parameter int QUEUE_SIZE = 4,
  parameter int PADDR_W = 30,
  parameter int DATA_SIZE = 64
)(
  input logic[DATA_SIZE-1:0] store_data,
  input logic[PADDR_W-1:0] paddr
);

endmodule

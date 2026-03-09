
//5 cycle request to response
//4 ways, pipt, write-back, 4 mshr (maybe 2)
//inclusive (l1 contents are in l2)
//30-bit paddr
module l2cache (
    input logic clk_in,
    
    //l1 to l2
    input logic l1_req_valid,
    input logic l1_req_rw,
    input logic [29:0] l1_req_paddr,
    input logic [511:0] l1_req_data,
    output logic l1_resp_valid,
    output logic [511:0] l1_resp_data,

    //TODO: l2 to dram
    //idk how i'm meant to write this tbh i think on the fpga it's gonna be mmio to the device
    //but i should wait and ask everyone

    //dram_ready
    //dram_valid
    //dram_mode
    //dram_paddr
    //dram_data
);
    //cache array

    //mshr
    
    //lru manager

    //lol pipeline?? prob this module but wtf that's evil T-T

    
endmodule

//make sub so i can use the parameter stuff
//source: https://www.chipverify.com/verilog/verilog-parameters
//i think if i implement with inline parameters we can get identifier issues

//paddr should be like [tag20,index4,offset6]
//maybe parametrize this as well though
module l2_cache_array #(
    parameter S = 16, 
    parameter A = 4,
    parameter B = 64,
    parameter C = 4096,
)(
    input logic clk_in,

    //read signals
    //sysver has packed vector notation that is REALLY good here
    //source: https://www.chipverify.com/systemverilog/systemverilog-arrays
    input logic [3:0] r_index,
    output logic [19:0] r_tag[(A-1):0],
    output logic [(B*8-1)-1:0] r_data[(A-1):0],
    output logic r_valid[(A-1): 0],
    output logic r_dirty[(A-1: 0)],

    //write signals
    input logic w_mode,
    input logic [3:0] w_index,
    input logic [1:0] w_dest,
    input logic [19:0] w_tag,
    input logic [(B*8-1):0] w_data,
    input logic w_valid,
    input logic w_dirty
);

    //vectors
    logic [19:0] tags [(S-1):0][(A-1):0];
    logic [(B*8-1):0] data [(S-1):0][(A-1):0];
    logic valids[(S-1):0][(A-1):0];
    logic dirtys[(S-1):0][(A-1):0];
    
    //write
    always_ff @(posedge clk_in) begin
        if(w_mode) begin //write enable, override entry
            tags[w_index][w_dest] <= w_tag;
            data[w_index][w_dest] <= w_data;
            valids[w_index][w_dest] <= w_valid;
            dirtys[w_index][w_dest] <= w_dirty;
        end
    end

    //read
    //i looked it up you can just check all ways in each set at once
    always_comb begin
        for(int w = 0; w < A; w++) begin
            r_tag[w] = tags[r_index][w];
            r_data[w] = data[r_index][w];
            r_valid[w] = valid[r_index][w];
            r_dirty[w] = valid[r_imdex][w];
        end
    end
endmodule

//tree slide is is mem5.6 slide 9
module l2_lru #(
    parameter S = 16
)(
    input clk_in,

    input logic update_mode,
    input logic [3:0] update_index,
    input logic [1:0] update_way,
    input logic [3:0] query_index,
    output logic [1:0] victim,
);

    logic [2:0] tree [(S-1):0];

    //find victim
    always_comb begin
        logic [2:0] t = tree[query_index];
        if(!t[2])
            victim = t[1] ? 2'd1 : 2'd0; //left
        else    
            victim = t[0] ? 2'd3 : 2'd2; //right
    end

    //update tree
    always_ff @(posedge clk_in) begin
        case (update_way)
            2'd0: tree[update_index] <= {1'b1, 1'b1, tree[update_index][0]};
            2'd1: tree[update_index] <= {1'b1, 1'b0, tree[update_index][0]};
            2'd2: tree[update_index] <= {1'b0, tree[update_index][1], 1'b1};
            2'd3: tree[update_index] <= {1'b0, tree[update_index][1], 1'b1};
        endcase
    end

endmodule

//mshr slide is mem5.6 slide 12
module l2_mshr #(
    parameter 
)(
    input
    output
);

endmodule

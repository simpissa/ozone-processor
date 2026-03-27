`timescale 1ns / 1ps

module test();

logic clk_in;
logic reset;

logic [47:0] load_vaddr;
logic [47:0] store_vaddr;
logic loadValid;
logic [3:0] load_id;
logic [3:0] store_id;
logic storeValid;
logic [63:0] store_data;
logic [3:0] load_id_completed;
logic [3:0] store_id_completed;
logic store_finished;
logic load_finished;

logic l1ready;
logic [63:0] data_out;
logic data_valid;

logic l2_req_valid;
logic l2_req_rw;
logic [23:0] l2_req_paddr;

logic [63:0] l2_req_data;
logic [3:0] l2_query_id;
logic l2_evict_valid;
logic [511:0] l2_evict_data;
logic l2_ready_for_resp;

logic l2_resp_valid;
logic [511:0] l2_resp_data;
logic [3:0] l2_resp_id;
logic [23:0] l2_paddr;

logic [29:0] tlb_paddr_in;
logic tlb_paddr_ready;
logic [47:0] tlb_vaddr_out;
logic tlb_vaddr_valid;


l1cache #() dut (
    .clk(clk_in),
    .reset(reset),
    .load_vaddr(load_vaddr),
    .store_vaddr(store_vaddr),
    .loadValid(loadValid),
    .load_id(load_id),
    .store_id(store_id),
    .storeValid(storeValid),
    .store_data(store_data),
    .load_id_completed(load_id_completed),
    .store_id_completed(store_id_completed),
    .store_finished(store_finished),
    .load_finished(load_finished),
    .l1ready(l1ready),
    .data_out(data_out),
    .data_valid(data_valid),
    .l2_req_valid(l2_req_valid),
    .l2_req_rw(l2_req_rw),
    .l2_req_paddr(l2_req_paddr),
    .l2_req_data(l2_req_data),
    .l2_query_id(l2_query_id),
    .l2_evict_valid(l2_evict_valid),
    .l2_evict_data(l2_evict_data),
    .l2_ready_for_resp(l2_ready_for_resp),
    .l2_resp_valid(l2_resp_valid),
    .l2_resp_data(l2_resp_data),
    .l2_resp_id(l2_resp_id),
    .l2_paddr(l2_paddr),
    .tlb_paddr_in(tlb_paddr_in),
    .tlb_paddr_ready(tlb_paddr_ready),
    .tlb_vaddr_out(tlb_vaddr_out),
    .tlb_vaddr_valid(tlb_vaddr_valid)
);

initial begin
    clk_in = 0;
    forever begin
        #5 clk_in = ~clk_in;
    end
end

task test1;
    
endtask


endmodule

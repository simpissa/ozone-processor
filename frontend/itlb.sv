`timescale 1ns / 1ps

module itlb #(
    parameter int VA_BITS = 48,
    localparam VPN_BITS = VADDR_W - 12,
    localparam PPN_BITS = 18,
    localparam ENTRIES = 16
) (

    input logic         clk,
    input logic         reset,
    
    // system register
    input logic [63:0]  ttbr0,
    
    // fetch
    input logic [63:0]  fetch_vaddr_i, // may need to be VA_BITS-1 instead of 63
    output logic        fetch_hit_o,
    output logic [29:0] fetch_paddr_o,
    output logic        fetch_miss_o,

    // memory
    input logic         mem_ready_i,
    input logic         mem_valid_i,
    input logic [511:0] mem_rdata_i,
    output logic [29:0] mem_addr_o,
    output logic        mem_valid_o
);

typedef struct packed {
    logic valid;
    logic [VPN_BITS-1:0] vpn;
    logic [PPN_BITS-1:0] ppn;
} tlb_entry_t;

logic [VPN_BITS-1:0] vpn;
logic [63:0] pte_addr;
logic [2:0] pte_idx;
logic [63:0] pte;

tlb_entry_t tlb_table [ENTRIES];
logic [3:0] evict_idx;

logic request_pending;

assign vpn = fetch_vaddr_i[VA_BITS-1:12];
assign pte_addr = ttbr0 + (vpn << 3);
assign mem_addr_o = pte_addr[29:6];
assign pte_idx = vpn[2:0];
assign pte = (mem_rdata_i >> (pte_idx * 64))[63:0];

initial begin
    for (int i = 0; i < ENTRIES; ++i) begin
        tlb_table[i].valid = 0;
    end
    evict_idx = '0;
    request_pending = 0;
end

always_comb begin
    fetch_miss_o = 1;
    fetch_hit_o = 0;
    evict_idx = '0;

    for (int i = 0; i < ENTRIES; ++i) begin
        if (tlb_table[i].valid && tlb_table[i].vpn == vpn) begin
            fetch_hit_o = 1;
            fetch_paddr_o = {tlb_table[i].ppn, fetch_vaddr_i[11:0]};
            fetch_miss_o = 0;
        end else if (!tlb_table[i].valid) begin
            evict_idx = 4'(i);
        end
    end

end

always_ff @(posedge clk) begin

    if (fetch_miss_o && !request_pending) begin
        mem_valid_o <= 1;
        request_pending <= 1;

        // there it's entirely possible there is a big here
        // where we have put in a new request, but the valid
        // bit is still set for our previous request and then
        // we go and pick it up. i guess i can pray it doesn't
        // work like that for now
        if (mem_valid_i) begin
            if (pte[0]) begin
                tlb_table[evict_idx].valid <= 1;  
                tlb_table[evict_idx].vpn <= vpn;
                tlb_table[evict_idx].ppn <= pte[29:12];
            end else begin
                // assert 0 for now, but find a way to throw an exception
                assert(0);
            end
            request_pending <= 0;
        end
    end
    
    // assume they hear our request
    if (mem_valid_o && mem_ready_i)
        mem_valid_o <= 0;

    if (reset) begin
        for (int i = 0; i < ENTRIES; ++i) begin
            tlb_table[i].valid <= 0;
            tlb_table[i].ppn <= '0;
            tlb_table[i].vpn <= '0;
        end
    end 
    
end

endmodule



`timescale 1ns / 1ps

module itlb #(
    parameter int VA_BITS = 48,
    localparam VPN_BITS = VA_BITS - 12,
    localparam PPN_BITS = 18,
    localparam ENTRIES = 16
) (

    input logic         clk,
    input logic         reset,
    
    // system register
    input logic [63:0]  ttbr0,
    
    // fetch
    input logic         fetch_valid_i,
    input logic [63:0]  fetch_vaddr_i, // may need to be VA_BITS-1 instead of 63
    output logic        fetch_hit_o,
    output logic [29:0] fetch_paddr_o,
    output logic        fetch_miss_o,
    output logic        fetch_ready_o,

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
logic [VPN_BITS-1:0] vpn_lookup;
logic [11:0] vaddr_offset;

tlb_entry_t tlb_table [ENTRIES];
logic [3:0] evict_idx;

logic request_pending;
logic lookup_valid;
logic fill_hit;
logic table_hit;

assign vpn = fetch_vaddr_i[VA_BITS-1:12];
assign pte_addr = ttbr0 + ({{(64-VPN_BITS){1'b0}}, vpn_lookup} << 3);
assign mem_addr_o = {pte_addr[29:6], 6'b0};
assign pte_idx = vpn_lookup[2:0];
assign pte = mem_rdata_i[pte_idx*64 +: 64];
assign fill_hit = lookup_valid && request_pending && mem_valid_i && pte[0];

logic DBG;

initial begin
    if (!$value$plusargs("IDEBUG=%d", DBG))
        DBG = 0;

    for (int i = 0; i < ENTRIES; ++i) begin
        tlb_table[i].valid = 0;
    end
    request_pending = 0;
    lookup_valid = 0;
    fetch_ready_o = 0;
    mem_valid_o = 0;
end

always_comb begin
    
    fetch_miss_o = 1;
    fetch_hit_o = 0;
    table_hit = 0;
    evict_idx = '0;
    fetch_paddr_o = '0;

    if (DBG)
        $display("iTLB State: Checking table for vpn %x, valid %d", vpn_lookup, lookup_valid);

    for (int i = 0; i < ENTRIES; ++i) begin
        if (tlb_table[i].valid && tlb_table[i].vpn == vpn_lookup) begin
            if (DBG)
                $display("iTLB State: Hit in table at idx %d", i);
            table_hit = 1;
            fetch_paddr_o = {tlb_table[i].ppn, vaddr_offset};
            break;
        end else if (!tlb_table[i].valid) begin
            evict_idx = 4'(i);
        end
    end

    if (fill_hit) begin
        fetch_paddr_o = {pte[29:12], vaddr_offset};
    end

    fetch_hit_o = lookup_valid && (table_hit || fill_hit);
    fetch_miss_o = lookup_valid && !(table_hit || fill_hit);

    if (DBG)
        $display("iTLB State: Done checking table, hit %d miss %d", fetch_hit_o, fetch_miss_o);

end

always_ff @(posedge clk) begin

    if (fetch_ready_o && fetch_valid_i) begin
        if (DBG)
            $display("iTLB State: Firing lookup");
        vpn_lookup <= vpn;
        vaddr_offset <= fetch_vaddr_i[11:0];
        fetch_ready_o <= 0;
        lookup_valid <= 1;
    end

    if (fetch_miss_o && !request_pending && !mem_valid_o) begin
        if (DBG)
            $display("iTLB State: Sending request to memory unit");
        mem_valid_o <= 1;
        request_pending <= 1;
    end

    if (mem_valid_i && request_pending) begin
        if (DBG)
            $display("iTLB State: Memory is valid, reading in table values...");

        if (pte[0]) begin

            if (DBG)
                $display("Found ppn %x", pte[29:12]);
            tlb_table[evict_idx].valid <= 1;  
            tlb_table[evict_idx].vpn <= vpn_lookup;
            tlb_table[evict_idx].ppn <= pte[29:12];
        end else begin
            // assert 0 for now, but find a way to throw an exception
            // TODO: im assuming now that the only time a fetch is unmapped is RET to 0x0, so I handle it in the rob
            //              if theres any test case where this isn't true we'll have to handle that
            assert(0);
        end
        request_pending <= 0;
        fetch_ready_o <= 1;
        lookup_valid <= 0;
    end

    if (table_hit && lookup_valid) begin
        fetch_ready_o <= 1;
        lookup_valid <= 0;
    end

    // assume they hear our request
    if (mem_valid_o && mem_ready_i) begin
        if (DBG)
            $display("iTLB State: Assuming memory found our request, invalidating request");
        mem_valid_o <= 0;
    end

    if (reset) begin
        if (DBG)
            $display("iTLB State: Resetting...");
        for (int i = 0; i < ENTRIES; ++i) begin
            tlb_table[i].valid <= 0;
            tlb_table[i].ppn <= '0;
            tlb_table[i].vpn <= '0;
        end
        lookup_valid <= 0;
        request_pending <= 0;
        mem_valid_o <= 0;
        fetch_ready_o <= 1;
    end 
    
end

endmodule

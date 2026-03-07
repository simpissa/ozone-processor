`timescale 1ns / 1ps

module tlb #(
    parameter int PAGE_OFF_W = 12,
    parameter int VADDR_W = 48,
    parameter int PADDR_W = 30,
    parameter int ENTRIES = 16,
    parameter int ID_W = 4
) (
    input logic clk,
    input logic rst,

    input logic lookup_valid,
    input logic [VADDR_W-1:0] lookup_vaddr,
    input logic [ID_W-1:0] lookup_id,
    output logic lookup_ready,

    output logic resp_valid,
    output logic [ID_W-1:0] resp_id,
    output logic resp_hit,
    output logic [PADDR_W-1:0] resp_paddr,

    input logic fill_valid,
    input logic [VADDR_W-1:0] fill_vaddr,
    input logic [PADDR_W-1:0] fill_paddr,
    output logic fill_ready
);

    localparam int VPN_W = VADDR_W - PAGE_OFF_W;
    localparam int PPN_W = PADDR_W - PAGE_OFF_W;
    localparam int IDX_W = $clog2(ENTRIES);

    logic [ENTRIES-1:0] valid;
    logic [VPN_W-1:0] vpn [0:ENTRIES-1];
    logic [PPN_W-1:0] ppn [0:ENTRIES-1];
    logic lru_mat [0:ENTRIES-1][0:ENTRIES-1];

    logic [VPN_W-1:0] lookup_vpn;
    logic [PAGE_OFF_W-1:0] lookup_off;
    logic [VPN_W-1:0] fill_vpn;
    logic [PPN_W-1:0] fill_ppn;

    logic [ENTRIES-1:0] lookup_hit_vec;
    logic lookup_hit_any;
    logic [IDX_W-1:0] lookup_hit_idx;
    logic [PPN_W-1:0] lookup_hit_ppn;

    logic [ENTRIES-1:0] fill_hit_vec;
    logic fill_hit_any;
    logic [IDX_W-1:0] fill_hit_idx;

    logic invalid_any;
    logic [IDX_W-1:0] first_invalid_idx;
    logic [ENTRIES-1:0] lru_row_zero;
    logic [IDX_W-1:0] lru_victim_idx;
    logic [IDX_W-1:0] fill_target_idx;

    logic lookup_fire;

    // always ready
    assign lookup_ready = 1'b1;
    assign fill_ready = 1'b1;
    assign lookup_fire = lookup_valid && lookup_ready;

    assign lookup_vpn = lookup_vaddr[VADDR_W-1:PAGE_OFF_W];
    assign lookup_off = lookup_vaddr[PAGE_OFF_W-1:0];
    assign fill_vpn = fill_vaddr[VADDR_W-1:PAGE_OFF_W];
    assign fill_ppn = fill_paddr[PADDR_W-1:PAGE_OFF_W];

    // check for lookup/fill hits
    genvar i;
    generate
        for (i = 0; i < ENTRIES; i = i + 1) begin : gen_hit_vec
            assign lookup_hit_vec[i] = valid[i] && (vpn[i] == lookup_vpn);
            assign fill_hit_vec[i] = valid[i] && (vpn[i] == fill_vpn);
        end
    endgenerate

    assign lookup_hit_any = |lookup_hit_vec;
    assign fill_hit_any = |fill_hit_vec;
    assign invalid_any = |(~valid);

    // get idxs of hits/invalid/victim
    always_comb begin
        lookup_hit_idx = '0;
        fill_hit_idx = '0;
        first_invalid_idx = '0;
        lru_victim_idx = '0;

        for (int i = ENTRIES-1; i >= 0; i = i-1) begin
            if (lookup_hit_vec[i]) begin
                lookup_hit_idx = i[IDX_W-1:0];
            end
            if (fill_hit_vec[i]) begin
                fill_hit_idx = i[IDX_W-1:0];
            end
            if (!valid[i]) begin
                first_invalid_idx = i[IDX_W-1:0];
            end
            if (lru_row_zero[i]) begin
                lru_victim_idx = i[IDX_W-1:0];
            end
        end
    end

    assign lookup_hit_ppn = ppn[lookup_hit_idx];

    // update lru victim TODO: prob need to make this more efficient
    always_comb begin
        for (int i = 0; i < ENTRIES; i = i+1) begin
            lru_row_zero[i] = 1'b1;
            for (int j = 0; j < ENTRIES; j = j+1) begin
                if ((i != j) && lru_mat[i][j]) begin
                    lru_row_zero[i] = 1'b0;
                end
            end
        end
    end

    // hit -> invalid -> lru victim
    assign fill_target_idx = fill_hit_any ? fill_hit_idx :
                             invalid_any ? first_invalid_idx :
                                            lru_victim_idx;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid <= '0;
            resp_valid <= 1'b0;
            resp_id <= '0;
            resp_hit <= 1'b0;
            resp_paddr <= '0;

            for (int i = 0; i < ENTRIES; i = i+1) begin
                vpn[i] <= '0; // not rlly needed
                ppn[i] <= '0;
                for (int j = 0; j < ENTRIES; j = j+1) begin
                    lru_mat[i][j] <= 1'b0;
                end
            end
        end else begin
            resp_valid <= lookup_fire;
            if (lookup_fire) begin
                resp_id <= lookup_id;
                resp_hit <= lookup_hit_any;
                resp_paddr <= lookup_hit_any ? {lookup_hit_ppn, lookup_off} : '0;
            end else begin
                resp_id <= '0; resp_hit <= 1'b0; resp_paddr <= '0; end
            if (fill_valid) begin
                valid[fill_target_idx] <= 1'b1;
                vpn[fill_target_idx] <= fill_vpn;
                ppn[fill_target_idx] <= fill_ppn;

                for (int j = 0; j < ENTRIES; j = j+1) begin
                    if (j == int'(fill_target_idx)) begin
                        lru_mat[fill_target_idx][j] <= 1'b0;
                    end else begin
                        lru_mat[fill_target_idx][j] <= 1'b1;
                        lru_mat[j][fill_target_idx] <= 1'b0;
                    end
                end
            end

            // lookup lru priority over fill
            if (lookup_fire && lookup_hit_any) begin
                for (int j = 0; j < ENTRIES; j = j + 1) begin
                    if (j == int'(lookup_hit_idx)) begin
                        lru_mat[lookup_hit_idx][j] <= 1'b0;
                    end else begin
                        lru_mat[lookup_hit_idx][j] <= 1'b1;
                        lru_mat[j][lookup_hit_idx] <= 1'b0;
                    end
                end
            end
        end
    end

endmodule

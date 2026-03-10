// cmd: verilator --binary --timing --top-module tlb_tb tlb.sv tests/tlb_tb.sv && ./obj_dir/Vtlb_tb
`timescale 1ns / 1ps

module tlb_tb;
    localparam int PAGE_OFF_W = 4;
    localparam int VADDR_W = 16;
    localparam int PADDR_W = 16;
    localparam int ENTRIES = 4;
    localparam int ID_W = 3;
    localparam int VPN_W = VADDR_W - PAGE_OFF_W;
    localparam int PPN_W = PADDR_W - PAGE_OFF_W;

    logic clk;
    logic rst;

    logic lookup_valid;
    logic [VADDR_W-1:0] lookup_vaddr;
    logic [ID_W-1:0] lookup_id;
    logic lookup_ready;

    logic resp_valid;
    logic [ID_W-1:0] resp_id;
    logic resp_hit;
    logic [PADDR_W-1:0] resp_paddr;

    logic fill_valid;
    logic [2:0] trace_op;
    logic [VADDR_W-1:0] fill_vaddr;
    logic [PADDR_W-1:0] fill_paddr;
    logic fill_ready;

    tlb #(
        .PAGE_OFF_W(PAGE_OFF_W),
        .VADDR_W(VADDR_W),
        .PADDR_W(PADDR_W),
        .ENTRIES(ENTRIES),
        .ID_W(ID_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .lookup_valid(lookup_valid),
        .lookup_vaddr(lookup_vaddr),
        .lookup_id(lookup_id),
        .lookup_ready(lookup_ready),
        .resp_valid(resp_valid),
        .resp_id(resp_id),
        .resp_hit(resp_hit),
        .resp_paddr(resp_paddr),
        .fill_valid(fill_valid),
        .trace_op(trace_op),
        .fill_vaddr(fill_vaddr),
        .fill_paddr(fill_paddr),
        .fill_ready(fill_ready)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    task automatic do_reset;
        begin
            rst = 1'b1;
            lookup_valid = 1'b0;
            fill_valid = 1'b0;
            trace_op = 3'd0;
            repeat (2) @(posedge clk);
            #1;
            rst = 1'b0;
        end
    endtask

    task automatic fill_entry(
        input logic [VPN_W-1:0] vpn_i,
        input logic [PPN_W-1:0] ppn_i
    );
        begin
            @(negedge clk);
            fill_valid = 1'b1;
            trace_op = 3'd4;
            fill_vaddr = {vpn_i, {PAGE_OFF_W{1'b0}}};
            fill_paddr = {ppn_i, {PAGE_OFF_W{1'b0}}};
            lookup_valid = 1'b0;

            @(posedge clk);
            #1;
            fill_valid = 1'b0;
            trace_op = 3'd0;
        end
    endtask

    task automatic expect_lookup(
        input string tag,
        input logic [VPN_W-1:0] vpn_i,
        input logic [PAGE_OFF_W-1:0] off_i,
        input logic [ID_W-1:0] id_i,
        input logic exp_hit,
        input logic [PPN_W-1:0] exp_ppn
    );
        logic [PADDR_W-1:0] exp_paddr;
        begin
            exp_paddr = {exp_ppn, off_i};

            @(negedge clk);
            lookup_valid = 1'b1;
            lookup_vaddr = {vpn_i, off_i};
            lookup_id = id_i;
            fill_valid = 1'b0;

            @(posedge clk);
            #1;

            if (resp_valid !== 1'b1) begin
                $fatal(1, "[%s] lookup did not produce valid", tag);
            end
            if (resp_id !== id_i) begin
                $fatal(1, "[%s] resp_id wrong exp=%0d got=%0d", tag, id_i, resp_id);
            end
            if (resp_hit !== exp_hit) begin
                $fatal(1, "[%s] resp_hit mismatch exp=%0d got=%0d", tag, exp_hit, resp_hit);
            end
            if (exp_hit) begin
                if (resp_paddr !== exp_paddr) begin
                    $fatal(1, "[%s] resp_paddr mismatch exp=%0h got=%0h", tag, exp_paddr, resp_paddr);
                end
            end else begin
                if (resp_paddr !== '0) begin
                    $fatal(1, "[%s] resp_paddr should be zero on miss got=%0h", tag, resp_paddr);
                end
            end

            lookup_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        lookup_valid = 1'b0;
        lookup_vaddr = '0;
        lookup_id = '0;
        fill_valid = 1'b0;
        fill_vaddr = '0;
        fill_paddr = '0;

        do_reset();

        // vpn, offset, id, exp hit, exp ppn

        // reset state should miss
        expect_lookup("1", 12'h010, 4'h3, 3'h1, 1'b0, '0);

        // fill and basic translation
        fill_entry(12'h010, 12'h0A0);
        expect_lookup("2", 12'h010, 4'h5, 3'h2, 1'b1, 12'h0A0);

        // lru victim check with 4 entries
        do_reset();
        fill_entry(12'h001, 12'h101);
        fill_entry(12'h002, 12'h102);
        fill_entry(12'h003, 12'h103);
        fill_entry(12'h004, 12'h104);

        // evict vpn1 001
        fill_entry(12'h005, 12'h105);

        expect_lookup("3", 12'h001, 4'h2, 3'h5, 1'b0, '0);
        expect_lookup("4", 12'h005, 4'h2, 3'h6, 1'b1, 12'h105);
        expect_lookup("5", 12'h002, 4'h2, 3'h7, 1'b1, 12'h102);

        // same-cycle fill + lookup-hit should prioritize lookup lru update
        do_reset();
        fill_entry(12'h001, 12'h201);
        fill_entry(12'h002, 12'h202);
        fill_entry(12'h003, 12'h203);
        fill_entry(12'h004, 12'h204);

        @(negedge clk);
        lookup_valid = 1'b1;
        lookup_vaddr = {12'h002, 4'h9};
        lookup_id = 3'h1;
        fill_valid = 1'b1;
        trace_op = 3'd4;
        fill_vaddr = {12'h005, 4'h0};
        fill_paddr = {12'h205, 4'h0};

        @(posedge clk);
        #1;

        if (resp_valid !== 1'b1) begin
            $fatal(1, "[6] lookup did not produce resp_valid");
        end
        if (resp_id !== 3'h1) begin
            $fatal(1, "[6] resp_id mismatch exp=%0d got=%0d", 3'h1, resp_id);
        end
        if (resp_hit !== 1'b1) begin
            $fatal(1, "[6] lookup should hit");
        end
        if (resp_paddr !== {12'h202, 4'h9}) begin
            $fatal(1, "[6] resp_paddr mismatch exp=%0h got=%0h", {12'h202, 4'h9}, resp_paddr);
        end

        lookup_valid = 1'b0;
        fill_valid = 1'b0;
        trace_op = 3'd0;

        // 002 005 004 003
        fill_entry(12'h001, 12'h201);
        fill_entry(12'h003, 12'h203);
        // 003 001 002 005

        // if lookup has priority, next eviction is 005
        fill_entry(12'h006, 12'h206);
        //006 003 001 002

        expect_lookup("8", 12'h005, 4'h1, 3'h2, 1'b0, '0);
        expect_lookup("9", 12'h002, 4'h1, 3'h2, 1'b1, 12'h202);
        expect_lookup("10", 12'h001, 4'h1, 3'h2, 1'b1, 12'h201);
        expect_lookup("11", 12'h003, 4'h1, 3'h2, 1'b1, 12'h203);
        expect_lookup("12", 12'h006, 4'h1, 3'h2, 1'b1, 12'h206);

        $display("PASSED TESTS");
        $finish;
    end
endmodule

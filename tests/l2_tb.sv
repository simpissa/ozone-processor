`timescale 1ns / 1ps

module l2_tb;
    localparam int PADDR_W = 30;
    localparam int BLOCK_SIZE = 64;
    localparam int NUM_WAYS = 4;
    localparam int CAPACITY = 4096;
    localparam int NUM_MSHRS = 4;
    localparam int MSHR_QUEUE_SIZE = 4;
    localparam int ID_LENGTH = 4;
    localparam int OFFSET_SIZE = $clog2(BLOCK_SIZE);
    localparam int WORD_ADDR_SIZE = PADDR_W - OFFSET_SIZE;
    localparam int LINE_W = BLOCK_SIZE * 8;

    logic clk;
    logic rst;

    logic l1_req_valid;
    logic l1_req_rw;
    logic [WORD_ADDR_SIZE-1:0] l1_req_paddr;
    logic [LINE_W-1:0] l1_req_data;
    logic [ID_LENGTH-1:0] l1_query_id;
    logic l1_ready_for_input;

    logic l1_resp_valid;
    logic [LINE_W-1:0] l1_resp_data;
    logic [ID_LENGTH-1:0] l1_output_id;

    logic sdram_req_valid;
    logic sdram_req_ready;
    logic sdram_req_rw;
    logic [31:0] sdram_req_addr;
    logic [LINE_W-1:0] sdram_req_wdata;

    logic sdram_resp_valid;
    logic [LINE_W-1:0] sdram_resp_rdata;

    logic pending_sdram_resp;
    logic [31:0] pending_sdram_addr;
    logic [LINE_W-1:0] pending_sdram_data;

    int sdram_read_count;
    int sdram_write_count;

    l2cache #(
        .PADDR_W(PADDR_W),
        .BLOCK_SIZE(BLOCK_SIZE),
        .NUM_WAYS(NUM_WAYS),
        .CAPACITY(CAPACITY),
        .NUM_MSHRS(NUM_MSHRS),
        .MSHR_QUEUE_SIZE(MSHR_QUEUE_SIZE),
        .ID_LENGTH(ID_LENGTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .l1_req_valid(l1_req_valid),
        .l1_req_rw(l1_req_rw),
        .l1_req_paddr(l1_req_paddr),
        .l1_req_data(l1_req_data),
        .l1_query_id(l1_query_id),
        .l1_ready_for_input(l1_ready_for_input),
        .l1_resp_valid(l1_resp_valid),
        .l1_resp_data(l1_resp_data),
        .l1_output_id(l1_output_id),
        .sdram_req_valid(sdram_req_valid),
        .sdram_req_ready(sdram_req_ready),
        .sdram_req_rw(sdram_req_rw),
        .sdram_req_addr(sdram_req_addr),
        .sdram_req_wdata(sdram_req_wdata),
        .sdram_resp_valid(sdram_resp_valid),
        .sdram_resp_rdata(sdram_resp_rdata)
    );

    always #5 clk = ~clk;

    // Deterministic SDRAM line contents, just the requested addr in the top 32 bits
    function automatic logic [LINE_W-1:0] line_pattern(input logic [31:0] addr);
        logic [LINE_W-1:0] result;

        result = '0;
        result[LINE_W-1 -: 32] = addr;
        line_pattern = result;
    endfunction

    task automatic reset;
        begin
            rst = 1'b1;
            l1_req_valid = 1'b0;
            l1_req_rw = 1'b0;
            l1_req_paddr = '0;
            l1_req_data = '0;
            l1_query_id = '0;
            sdram_req_ready = 1'b1;
            sdram_resp_valid = 1'b0;
            sdram_resp_rdata = '0;
            pending_sdram_resp = 1'b0;
            pending_sdram_addr = '0;
            pending_sdram_data = '0;
            sdram_read_count = 0;
            sdram_write_count = 0;
            repeat (3) @(posedge clk);
            rst = 1'b0;
        end
    endtask

    // drive l1 request for one cycle once l2 is ready
    task automatic drive_request(
        input logic req_rw,
        input logic [WORD_ADDR_SIZE-1:0] req_paddr,
        input logic [LINE_W-1:0] req_data,
        input logic [ID_LENGTH-1:0] req_id
    );
        begin
            while (l1_ready_for_input !== 1'b1) begin
                @(posedge clk);
            end

            @(negedge clk);
            l1_req_valid = 1'b1;
            l1_req_rw = req_rw;
            l1_req_paddr = req_paddr;
            l1_req_data = req_data;
            l1_query_id = req_id;

            @(posedge clk);
            @(negedge clk);
            l1_req_valid = 1'b0;
            l1_req_rw = 1'b0;
            l1_req_paddr = '0;
            l1_req_data = '0;
            l1_query_id = '0;
        end
    endtask

    // check SDRAM read request when valid
    task automatic expect_sdram_read(input logic [31:0] expected_addr);
        int cycles;
        begin
            cycles = 0;
            while (!(sdram_req_valid && sdram_req_ready && !sdram_req_rw)) begin
                @(posedge clk);
                cycles++;
                if (cycles > 100) begin
                    $fatal(1, "response to sdram timed out");
                end
            end

            #1;
            if (sdram_req_addr !== expected_addr) begin
                $fatal(1, "SDRAM read addr mismatch exp=%08h got=%08h", expected_addr, sdram_req_addr);
            end
        end
    endtask

    // check SDRAM write request when valid
    task automatic expect_sdram_write(
        input logic [31:0] expected_addr,
        input logic [LINE_W-1:0] expected_data
    );
        int cycles;
        begin
            cycles = 0;
            while (!(sdram_req_valid && sdram_req_ready && sdram_req_rw)) begin
                @(posedge clk);
                cycles++;
                if (cycles > 100) begin
                    $fatal(1, "writeback to sdram timed out");
                end
            end

            #1;
            if (sdram_req_addr !== expected_addr) begin
                $fatal(1, "SDRAM write addr mismatch exp=%08h got=%08h", expected_addr, sdram_req_addr);
            end
            if (sdram_req_wdata !== expected_data) begin
                $fatal(1, "SDRAM write data mismatch");
            end
        end
    endtask

    // Confirm no additional SDRAM reads happen over the next few cycles
    task automatic expect_no_new_sdram_reads(input int old_count, input int cycles);
        begin
            repeat (cycles) @(posedge clk);
            if (sdram_read_count !== old_count) begin
                $fatal(1, "unexpected extra SDRAM reads old=%0d new=%0d", old_count, sdram_read_count);
            end
        end
    endtask

    // check L2 response back to L1 
    task automatic expect_l1_response(
        input logic [ID_LENGTH-1:0] expected_id,
        input logic [LINE_W-1:0] expected_data
    );
        int cycles;
        begin
            cycles = 0;
            while (l1_resp_valid !== 1'b1) begin
                @(posedge clk);
                cycles++;
                if (cycles > 100) begin
                    $fatal(1, "response to l1 timed out");
                end
            end

            #1;
            if (l1_output_id !== expected_id) begin
                $fatal(1, "L1 response id mismatch exp=%0d got=%0d", expected_id, l1_output_id);
            end
            if (l1_resp_data !== expected_data) begin
                $fatal(1, "L1 response data mismatch");
            end
        end
    endtask

    // simple sdram: always ready, line data returned after one cycle
    // writes are just counted
    always_ff @(posedge clk) begin
        sdram_resp_valid <= 1'b0;

        if (sdram_req_valid && sdram_req_ready) begin
            if (sdram_req_rw) begin
                sdram_write_count <= sdram_write_count + 1;
            end else begin
                sdram_read_count <= sdram_read_count + 1;
                pending_sdram_resp <= 1'b1;
                pending_sdram_addr <= sdram_req_addr;
                pending_sdram_data <= line_pattern(sdram_req_addr);
            end
        end

        if (pending_sdram_resp) begin
            sdram_resp_valid <= 1'b1;
            sdram_resp_rdata <= pending_sdram_data;
            pending_sdram_resp <= 1'b0;
        end
    end

    initial begin
        logic [WORD_ADDR_SIZE-1:0] miss_addr;
        logic [WORD_ADDR_SIZE-1:0] set_addr_1;
        logic [WORD_ADDR_SIZE-1:0] set_addr_2;
        logic [WORD_ADDR_SIZE-1:0] set_addr_3;
        logic [WORD_ADDR_SIZE-1:0] set_addr_4;
        logic [31:0] expected_sdram_addr;
        logic [31:0] evict_addr;
        logic [31:0] fill_addr_1;
        logic [31:0] fill_addr_2;
        logic [31:0] fill_addr_3;
        logic [31:0] fill_addr_4;
        logic [LINE_W-1:0] expected_line;
        logic [LINE_W-1:0] fill_line_1;
        logic [LINE_W-1:0] fill_line_2;
        logic [LINE_W-1:0] fill_line_3;
        logic [LINE_W-1:0] fill_line_4;
        logic [LINE_W-1:0] write_line;
        int old_read_count;
        int old_write_count;

        clk = 1'b0;
        reset();

        miss_addr = 24'h001234;
        expected_sdram_addr = {2'b00, miss_addr, {OFFSET_SIZE{1'b0}}};
        expected_line = line_pattern(expected_sdram_addr);

        // first read to a line should miss and trigger SDRAM read
        drive_request(1'b0, miss_addr, '0, 4'h1);
        expect_sdram_read(expected_sdram_addr);
        expect_l1_response(4'h1, expected_line);
        if (sdram_read_count != 1) begin
            $fatal(1, "expected exactly one SDRAM read after first miss, got %0d", sdram_read_count);
        end

        // second read to the same line should hit in L2
        old_read_count = sdram_read_count;
        drive_request(1'b0, miss_addr, '0, 4'h2);
        expect_l1_response(4'h2, expected_line);
        expect_no_new_sdram_reads(old_read_count, 10);

        // write to the cached line
        write_line = {8{64'habcd_abcd_abcd_0001}};
        drive_request(1'b1, miss_addr, write_line, 4'h3);
        repeat (5) @(posedge clk);

        // read to same line should return the modified line without sending to SDRAM
        old_read_count = sdram_read_count;
        drive_request(1'b0, miss_addr, '0, 4'h4);
        expect_l1_response(4'h4, write_line);
        expect_no_new_sdram_reads(old_read_count, 5);

        // test dirty eviction of miss_addr
        // all same set as miss_addr h001234
        set_addr_1 = 24'h111114;
        set_addr_2 = 24'h222224;
        set_addr_3 = 24'h333334;
        set_addr_4 = 24'h444444;

        fill_addr_1 = {2'b00, set_addr_1, {OFFSET_SIZE{1'b0}}};
        fill_addr_2 = {2'b00, set_addr_2, {OFFSET_SIZE{1'b0}}};
        fill_addr_3 = {2'b00, set_addr_3, {OFFSET_SIZE{1'b0}}};
        fill_addr_4 = {2'b00, set_addr_4, {OFFSET_SIZE{1'b0}}};
        fill_line_1 = line_pattern(fill_addr_1);
        fill_line_2 = line_pattern(fill_addr_2);
        fill_line_3 = line_pattern(fill_addr_3);
        fill_line_4 = line_pattern(fill_addr_4);
        evict_addr = expected_sdram_addr;

        drive_request(1'b0, set_addr_1, '0, 4'h5);
        expect_sdram_read(fill_addr_1);
        expect_l1_response(4'h5, fill_line_1);

        drive_request(1'b0, set_addr_2, '0, 4'h6);
        expect_sdram_read(fill_addr_2);
        expect_l1_response(4'h6, fill_line_2);

        drive_request(1'b0, set_addr_3, '0, 4'h7);
        expect_sdram_read(fill_addr_3);
        expect_l1_response(4'h7, fill_line_3);

        old_read_count = sdram_read_count;
        old_write_count = sdram_write_count;
        drive_request(1'b0, set_addr_4, '0, 4'h8);
        expect_sdram_write(evict_addr, write_line);
        expect_sdram_read(fill_addr_4);
        expect_l1_response(4'h8, fill_line_4);
        assert(sdram_write_count==old_write_count+1);
        assert(sdram_read_count==old_read_count + 1);

        $display("PASS L2 TESTS");
        $finish;
    end
endmodule

module sdram (
    input  logic         clk,
    input  logic         reset,

    // external l2 communication
    // TODO: if l2 is supposed to be able to give dram multiple requests at a time, 
    //          there should be a mshr tag i/o as well, idt this is required tho
    input  logic         req_valid,
    output logic         req_ready,
    input  logic         req_rw,          // 0 = read line, 1 = write line
    input  logic [31:0]  req_addr,        // byte address
    input  logic [511:0] req_wdata,       // one full cache line

    output logic         resp_valid,
    output logic [511:0] resp_rdata,

    output logic         busy,

    // avalon mm port
    output logic         avm_m0_read,
    output logic         avm_m0_write,
    output logic [255:0] avm_m0_writedata,
    output logic [31:0]  avm_m0_address,
    input  logic [255:0] avm_m0_readdata,
    input  logic         avm_m0_readdatavalid,
    output logic [31:0]  avm_m0_byteenable,
    input  logic         avm_m0_waitrequest,
    output logic [10:0]  avm_m0_burstcount
    );

    typedef enum logic [2:0] {
        S_IDLE        = 3'd0, // wait for a new l2 request
        S_ISSUE_READ  = 3'd1, // launch a read burst to avalon
        S_WAIT_READ   = 3'd2, // collect read beats from avalon
        S_ISSUE_WRITE = 3'd3, // issue a 2-beat write burst and send beat 0
        S_WAIT_WRITE  = 3'd4, // keep the burst active and send beat 1
        S_RESP        = 3'd5  // report completion back to l2
    } state_t;

    state_t cur_state, next_state;

    logic [31:0]  req_addr_r;
    logic [511:0] req_wdata_r;

    logic [255:0] read_buf_lo;
    logic [1:0]   read_beats_seen;

    logic [31:0]  req_addr_aligned;

    // force 64B line alignment
    assign req_addr_aligned = {req_addr[31:6], 6'b0};

    always_ff @(posedge clk) begin
        if (reset) begin
        cur_state <= S_IDLE;
        end else begin
        cur_state <= next_state;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
        req_addr_r <= 32'd0;
        req_wdata_r <= 512'd0;
        end else begin
        if (cur_state == S_IDLE && req_valid && req_ready) begin
            req_addr_r <= req_addr_aligned;
            req_wdata_r <= req_wdata;
        end
        end
    end

    // read data
    always_ff @(posedge clk) begin
        if (reset) begin
        read_buf_lo <= 256'd0;
        read_beats_seen <= 2'd0;
        end else begin
        if (cur_state == S_IDLE) begin
            read_beats_seen <= 2'd0;
        end else if (cur_state == S_WAIT_READ && avm_m0_readdatavalid) begin
            case (read_beats_seen)
            2'd0: begin
                read_buf_lo <= avm_m0_readdata;
                read_beats_seen <= 2'd1;
            end
            2'd1: begin
                read_beats_seen <= 2'd2;
            end
            default: begin
                read_beats_seen <= read_beats_seen;
            end
            endcase
        end
        end
    end

    // response
    always_ff @(posedge clk) begin
        if (reset) begin
        resp_rdata <= 512'd0;
        end else begin
        if (cur_state == S_WAIT_READ && avm_m0_readdatavalid && read_beats_seen == 2'd1) begin
            // second beat just arrived this cycle
            resp_rdata <= {avm_m0_readdata, read_buf_lo};
        end else if (cur_state == S_WAIT_WRITE && !avm_m0_waitrequest) begin
            resp_rdata <= 512'd0;
        end
        end
    end

    // fsm
    always_comb begin
        next_state = cur_state;

        case (cur_state)
            S_IDLE: begin
                if (req_valid) begin
                if (req_rw) next_state = S_ISSUE_WRITE;
                else next_state = S_ISSUE_READ;
                end
            end

            S_ISSUE_READ: begin
                if (!avm_m0_waitrequest) begin
                    next_state = S_WAIT_READ;
                end
            end

            S_WAIT_READ: begin
                if (avm_m0_readdatavalid && read_beats_seen == 2'd1) begin
                    next_state = S_RESP;
                end
            end

            S_ISSUE_WRITE: begin
                if (!avm_m0_waitrequest) begin
                    next_state = S_WAIT_WRITE;
                end
            end

            S_WAIT_WRITE: begin
                if (!avm_m0_waitrequest) begin
                    next_state = S_RESP;
                end
            end

            S_RESP: begin
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // output
    always_comb begin
        req_ready = 1'b0;
        resp_valid = 1'b0;
        busy = 1'b1;

        avm_m0_read = 1'b0;
        avm_m0_write = 1'b0;
        avm_m0_writedata = 256'd0;
        avm_m0_address = 32'd0;
        avm_m0_byteenable = 32'hFFFF_FFFF;
        avm_m0_burstcount = 11'd0;

        case (cur_state)
            S_IDLE: begin
                busy = 1'b0;
                req_ready = 1'b1;
            end

            S_ISSUE_READ: begin
                avm_m0_read = 1'b1;
                avm_m0_address = req_addr_r;
                avm_m0_burstcount = 11'd2;       // one 2-beat burst on a 256b port = 64B line
            end

            S_WAIT_READ: begin
            end

            S_ISSUE_WRITE: begin
                avm_m0_write = 1'b1;
                avm_m0_address = req_addr_r;
                avm_m0_burstcount = 11'd2;       // base address for the whole burst

                avm_m0_writedata = req_wdata_r[255:0];   // beat 0
            end

            S_WAIT_WRITE: begin
                avm_m0_write = 1'b1;
                avm_m0_address = req_addr_r;           // keep base address stable for burst
                avm_m0_burstcount = 11'd2;
                avm_m0_writedata = req_wdata_r[511:256]; // beat 1
            end

            S_RESP: begin
                resp_valid = 1'b1;
            end

            default: begin
            end
        endcase
    end

endmodule

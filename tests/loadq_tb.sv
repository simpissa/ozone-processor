`timescale 1ns / 1ps

module test ();

logic clk_in;
logic reset;

logic trace_valid;
logic [2:0] trace_op;
logic [3:0] trace_id;
logic [47:0] trace_vaddr;
logic trace_vaddr_is_valid;
logic [4:0] trace_age;
logic trace_ready;

logic sq_query_valid;
logic [47:0] sq_query_addr;
logic [3:0] sq_query_id;
logic [4:0] sq_query_age;
logic sq_forward_valid;
logic [63:0] sq_forward_data;
logic sq_conflict;
logic sq_miss;

logic l1_req_valid;
logic [47:0] l1_req_vaddr;
logic [3:0] l1_req_id;
logic l1_req_ready;

logic l1_resp_valid;
logic [3:0] l1_resp_id;
logic [63:0] l1_resp_data;

logic load_complete_valid;
logic [3:0] load_complete_id;
logic [63:0] load_complete_data;

load_queue #(.LQ_SIZE(8), .ID_W(4)) lq (
    .clk(clk_in),
    .reset(reset),
    .trace_valid(trace_valid),
    .trace_op(trace_op),
    .trace_id(trace_id),
    .trace_vaddr(trace_vaddr),
    .trace_vaddr_is_valid(trace_vaddr_is_valid),
    .trace_age(trace_age),
    .trace_ready(trace_ready),
    .sq_query_valid(sq_query_valid),
    .sq_query_addr(sq_query_addr),
    .sq_query_id(sq_query_id),
    .sq_query_age(sq_query_age),
    .sq_forward_valid(sq_forward_valid),
    .sq_forward_data(sq_forward_data),
    .sq_conflict(sq_conflict),
    .sq_miss(sq_miss),
    .l1_req_valid(l1_req_valid),
    .l1_req_vaddr(l1_req_vaddr),
    .l1_req_id(l1_req_id),
    .l1_req_ready(l1_req_ready),
    .l1_resp_valid(l1_resp_valid),
    .l1_resp_id(l1_resp_id),
    .l1_resp_data(l1_resp_data),
    .load_complete_valid(load_complete_valid),
    .load_complete_id(load_complete_id),
    .load_complete_data(load_complete_data)
);


initial begin
    clk_in = 0;
    forever begin
        #5 clk_in = ~clk_in;
    end
end


initial begin

    $display("\nBeginning load queue unit tests\n\n");
    // jump 1
    $display("Testing regular load function");
    
    // Tests regular load
    trace_op = 0;
    trace_id = 1;
    trace_vaddr = 10;
    trace_vaddr_is_valid = 1;
    trace_age = 2;
    trace_valid = 1;

    @(negedge clk_in);

    trace_valid = 0;

    @(negedge clk_in);
    
    assert(sq_query_valid);
    assert(sq_query_addr == trace_vaddr);
    assert(sq_query_id == trace_id);
    assert(sq_query_age == trace_age);

    sq_forward_data = 101010;
    sq_forward_valid = 1;

    @(negedge clk_in);
    @(negedge clk_in);

    assert(load_complete_valid);
    assert(load_complete_data == sq_forward_data);
    assert(load_complete_id == trace_id);

    $display("passed");
    $display();

    // jump 2
    $display("Testing OP_MEM_RESOLVE");

    reset = 1;
    @(negedge clk_in);
    reset = 0;

    trace_op = 0;
    trace_id = 3;
    trace_vaddr = 0;
    trace_vaddr_is_valid = 0;
    trace_age = 2;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);

    assert(!sq_query_valid);

    trace_op = 2;
    trace_vaddr = 10;
    trace_vaddr_is_valid = 1;
    trace_valid = 1;
    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);

    assert(sq_query_valid);
    assert(sq_query_addr == trace_vaddr);

    $display("passed");

    $display();

    // jump 3
    $display("Testing issue on non-head load instr");

    // Tests our ability to operate on a load that isn't the head

    reset = 1;
    sq_forward_data = 0;
    sq_forward_valid = 0;
    @(negedge clk_in);
    reset = 0;

    trace_op = 0;
    trace_id = 0;
    trace_vaddr = 0;
    trace_vaddr_is_valid = 0;
    trace_age = 0;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);
    assert(!sq_query_valid);
    trace_op = 0;
    trace_id = 1;
    trace_vaddr = 100;
    trace_vaddr_is_valid = 1;
    trace_age = 1;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);

    assert(sq_query_valid);
    assert(sq_query_addr == 100);
    assert(sq_query_id == 1);

    trace_op = 2;
    trace_id = 0;
    trace_vaddr = 1000;
    trace_vaddr_is_valid = 1;
    trace_age = 2;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);
    @(negedge clk_in);

    // want to make sure our query didn't get overwritten if we haven't gotten a response back
    assert(sq_query_valid);
    assert(sq_query_addr == 100);
    assert(sq_query_id == 1);

    sq_forward_data = 100;
    sq_forward_valid = 1;

    @(negedge clk_in);

    sq_forward_valid = 0;
    
    @(negedge clk_in);

    assert(!load_complete_valid);
    assert(sq_query_valid);
    assert(sq_query_id == 0);
    assert(sq_query_addr == 1000);

    sq_forward_data = 1000;
    sq_forward_valid = 1;
    
    @(negedge clk_in);
    sq_forward_valid = 0;

    assert(!sq_query_valid);
    @(negedge clk_in);

    assert(load_complete_valid);
    assert(load_complete_id == 0);
    assert(load_complete_data == 1000);

    @(negedge clk_in);

    assert(load_complete_valid);
    assert(load_complete_id == 1);
    assert(load_complete_data == 100);

    @(negedge clk_in);

    assert(!load_complete_valid);
    
    $display("passed");
    $display();

    // jump 4
    $display("Testing tricky queue add");

    // This tests adding to an empty queue that isn't at head = tail = 0

    reset = 1;
    @(negedge clk_in);
    reset = 0;

    trace_op = 0; trace_id = 0;
    trace_vaddr = 0;
    trace_vaddr_is_valid = 1;
    trace_age = 2;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);

    assert(sq_query_valid);
    sq_forward_data = 10;
    sq_forward_valid = 1;

    @(negedge clk_in);

    sq_forward_valid = 0;

    assert(!sq_query_valid);
    
    @(negedge clk_in);

    assert(load_complete_valid);
    assert(load_complete_data == 10);

    trace_op = 0;
    trace_id = 1;
    trace_vaddr = 10;
    trace_vaddr_is_valid = 1;
    trace_age = 3;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);
    
    assert(sq_query_valid);

    $display("passed");
    $display();

    // jump 5
    $display("Testing non-add to a full queue");

    @(negedge clk_in);
    reset = 1;
    @(negedge clk_in);
    reset = 0;

    // Test to make sure we don't overwrite with a full queue
    assert(trace_ready);
    for (int i = 0; i < 8; ++i) begin
        trace_id = 4'(i + 2);
        trace_vaddr = i * 10;
        trace_vaddr_is_valid = 0;
        trace_valid = 1;
        @(negedge clk_in);
    end

    trace_valid = 0;
    assert(!trace_ready);

    $display("passed");
    $display();

    // jump 6
    $display("Testing store queue conflict");

    reset = 1;
    @(negedge clk_in);
    reset = 0;
    
    // This tests the use of conflicts 
    trace_op = 0;
    trace_id = 1;
    trace_vaddr = 10;
    trace_vaddr_is_valid = 1;
    trace_age = 1;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in)
    
    assert(sq_query_valid);

    sq_conflict = 1;

    @(negedge clk_in);

    // visual test, shouldn't be issued and should show conflict

    assert(!sq_query_valid);

    trace_op = 2;
    trace_id = 2; // dual test, do we break if we resolve a non-existing trace_id?
    trace_vaddr = 20;
    trace_vaddr_is_valid = 1;
    trace_age = 2;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);

    assert(sq_query_valid);
    assert(sq_query_id == 1);
    assert(sq_query_addr == 10);

    $display("passed");
    $display();
    
    // jump 7
    $display("Testing data from cache");

    // Test cache!
    reset = 1;
    sq_conflict = 0;
    @(negedge clk_in);
    reset = 0;

    trace_op = 0;
    trace_id = 1;
    trace_vaddr = 10;
    trace_vaddr_is_valid = 1;
    trace_age = 1;
    trace_valid = 1;

    @(negedge clk_in);
    trace_valid = 0;
    @(negedge clk_in);

    assert(sq_query_valid);

    sq_miss = 1;

    @(negedge clk_in);
    sq_miss = 0;
    assert(!l1_req_valid);
    l1_req_ready = 1;
    @(negedge clk_in);

    assert(l1_req_valid);

    l1_resp_data = 10;
    l1_resp_id = 1;
    l1_resp_valid = 1;

    @(negedge clk_in);
    @(negedge clk_in);
    
    assert(load_complete_valid);
    assert(load_complete_id == 1);
    assert(load_complete_data == 10);

    $display("passed");

    $display();

    $display("All tests passed");
    

    $finish;
end
endmodule

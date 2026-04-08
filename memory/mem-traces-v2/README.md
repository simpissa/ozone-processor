# Traces

The traces for the simulator are described by the following SystemVerilog
struct. Though it is described in SystemVerilog, the traces are just binary
strings, and can be used by any programming language.

```
typedef enum logic[2:0] {
    OP_MEM_LOAD = 0, // perform a memory load
    OP_MEM_STORE = 1, // send a memory store
    OP_MEM_RESOLVE = 2, // resolve an unresolved address
    OP_TLB_FILL = 4 // fill a line of the TLB 
} op_e;
logic [120:0] trace_line;
op_e trace_op = trace_line[54:52];
logic [3:0] trace_id = trace_line[51:48];
logic [47:0] trace_vaddr = trace_line[47:0];
logic trace_vaddr_is_valid = trace_line[55]; // only relevant to mem operations
logic trace_value_is_valid = trace_line[120]; // only relevant to store operations
logic [63:0] trace_value = trace_line[119:56]; // only relevant to store operations
logic [29:0] trace_tlb_paddr = trace_line[85:56]; // only relevant to TLB fill operations 
```

## Trace Generation: Pin

Traces are generated using
[Pin](https://software.intel.com/sites/landingpage/pintool/docs/98484/Pin/html/index.html).
This is essentially a just-in-time compiler for assembly. Callbacks were
attached to every load and store to record some data.

## Traces Provided

There are many variations of just one trace - a very oddly coded matrix
multiply. The oddness is intentional. The trace contains tens of thousands of
operations and touches many vaddrs. The matrix multiplying code which was used
to generate the code is included for completeness, but likely wont help much.

To break down the traces in the `traces` dir:
- `.txt` files are the actual outputs of a run
- `.log` files are the parsed trace files. You can regenerate these.
- `.bin` files are the binary traces. This is simply an array of 16-byte
  values, stored little endian.
- files containing `_real` will contain traces that enter the pipeline
  unresolved
- files containing `_lsq88` are meant for separate load/store queues with 8
  entries each. Thus, the trace ID is partitioned between loads and stores.

## TLB Management

During trace generation, a **16-way fully associative TLB** is maintained using
**True LRU** replacement. When a memory access misses the TLB, an `OP_TLB_FILL`
record is inserted into the trace *before* the memory operation. The DE10-Nano
seems to want physical addrs to start at `0x20000000`. It's okay if you did not
implement true LRU for your TLB, that's fine. Any LRU should also work for
these traces. Even no replacement policy at all should get you past 5000 lines
of a trace, which is definitely a passing grade.

## Utilities

These can hopefully help your debugging! All tools are single files with no
dependencies. They can be built with the provided Makefile or just raw gcc.

### Parsing Trace Files
Display binary traces in a human-readable table format.
- Vaddr valid = VV
- Value valid = VvV
```
make parse_trace
./parse_trace [TRACE] [timestep_limit]
```

### Trace Replay
Replay a trace and report the final state of modified memory:
```
make replay_trace
./replay_trace [TRACE] [timestep_limit]
```
Use 0 to have no limit.

This tool tracks `STORE` and `RESOLVE` operations to reconstruct memory state
at any point in the trace. Of course, microarchitectural memory state spans the
whole memory heirarchy, but this should be a good helping hand. This is
essentially how I will grade your work, by comparisons with the replay. 

**Dependencies when Replaying Traces**

We want to maintain precise exceptions even with all the memory-level
parallelism present in our system. To do so, keep in mind only STOREs can
update architectural state. (Let's assume no loads with side effects, meaning
no MMIO). If an access causes an exception, no future STOREs must take place.
This means that a STORE can only be sent out of the LSQ if all previous
instructions have been executed without errors (bits in the TLB determine
access violations, not that we model this). The `replay_trace` has the behavior
needed for precise exceptions.

LOADs are fine to be dispatched out-of-order, but keep in mind a LOAD may be
dependent on previous STORE. This is uncommon, so advanced designs will
speculatively perform LOADs, but speculation requires a design to **validate**
and **correct misspeculations**.

### Verilog Trace Reader
You've been given `trace_reader.sv`, which simply reads a trace for you into
SystemVerilog. Currently it prints out a trace in a nice format. This is just
for your convenience. Do with this code as you wish.
```
verilator --binary trace_reader.sv
obj_dir/Vtrace_reader +TRACE_FILE=traces/dgemm3_real.bin
```

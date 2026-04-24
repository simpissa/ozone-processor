# Ozone Processor

## Overview

In this lab you will design an out-of-order processor with a useful testing
interface on the DE10-Nano. We affectionately call this the Ozone Processor.
We will will provide a large amount of code for the testing harness. Here is an
overview of the expected process:

1. On the DE10-Nano, a user will run a program on the HPS to communicate with
   the FPGA. The teaching staff have provided this tool. It is configured via
   config file and there is a `--help` flag describing it's use. This is what
   we will be use to grade. It can:
   - load programs into either the FPGAs memory or a Verilator testbench's
     memory
   - reset the ozone processor
   - poll the ozone processor for a completion signal
   - inspect the state of memory and registers after completion
2. The user will load a program into the the Ozone Processor's memory and then
   pass a reset signal to the ozone processor, and then begin to poll for the
   completion signal output by the ozone processor.
3. Upon receiving a reset signal, The ozone processor will begin executing in
   EL1, starting at a hardcoded entry point (set in the config). At EL1, the
   ozone processor is always direct mapped to DRAM.
4. The code beginning at the entry point is a "bootloader" for our program.
   The bootloader's runs at EL1. The bootloader's job is to:
   - set the special purpose registers relevant for this program (`SP_EL0`,
     `SPSR_EL1`, `ELR_EL1`).
   - write the EL0 memory mappings relevant for this particular program. The
     mappings will be stored in a single paged marked in the config. This single
     page will serve as the translation table for the ozone processor (or page
     table in x86 terms) and can hold at most 200 entries. A "page walk" will
     just be an O(1) lookup of this table by the ozone processor.
5. The ozone processor will reach an `ERET` instruction which switches to EL0
   and branches to the userspace program's entry point.
6. Upon jumping to userspace, the ozone processor will experience a TLB miss,
   upon which it perform a "page walk" to find its mapping, and then retry the
   instruction.
7. The ozone processor will run userspace code out-of-order. More details about
   the specs of the processor are detailed in a different section..
8. The final userspace instruction of the ozone processor will be a RET to 0x0.
   This is expected to cause an exception (which one?), which transfers control
   to EL1. Should you not do any extra credit, this is the only type of
   exception you will need to handle. (Is this true? imem exceptions?)
9. The segfault exception handler (location specified in config) will never
   return. This is done by writing a `terminate` value to the MSR `ACTLR_EL1`,
   which the ozone processor will use to fire a termination signal (and if
   running on the FPGA, blink a light to indicate the program has completed).
   The handler will then spinloop forever.
10. The HPS will see that the completion signal has been set and print out the
    modified memory state of the Ozone Processor.

## The Ozone Processor Spec

The following is expected of the processor:
- single core
- out-of-order with precise exceptions (meaning Tomasulo + ROB)
- cracks opcodes into micro-ops (deatiled below), destined for different
  functional units.
- contains a fully associative 16 line iTLB.
- contains a branch target buffer (BTB), updated on branch resolution
- contains a Two-Level Adaptive Branch Predictor, updated on branch resolution.
- contains at least 1 arithmetic unit (adder). We provide the unit.
- contains at least 1 shifter (ubfm, sbfm, lsrv). Reuse yours from the first
  project, or use the one we've provided.
- contains at least 1 logic unit (xor, and, or, not). You must create this.
- contains an address generation unit (AGU). This is just an adder which is
  used only to compute effective addresses.
- contains a memory unit. Reuse your unit from the memory project.
- contains at least 2 floating point units (need flop testcase?). We provide
  the units.

## Micro-Ops (uops)

| Opcode         | uOPs                      | Can Except? | Category       | Section  | Format |
|----------------|---------------------------|-------------|----------------|----------|--------|
| LDUR           | AGU+RD                    | Yes         | Memory         | C6.2.202 | M      |
| STUR           | AGU+WR                    | Yes         |                | C6.2.346 | M      |
|----------------|---------------------------|-------------|----------------|----------|--------|
| MOVK           | AND+OR                    |             | Immediates     | C6.2.225 | I1     |
| MOVZ           | OR w/ XZR                 |             |                | C6.2.227 | I1     |
| ADRP           | AND+ADD                   |             |                | C6.2.11  | I2     |
|----------------|---------------------------|-------------|----------------|----------|--------|
| ADD            | ADD                       |             | Computation    | C6.2.4   | RI     |
| ADDS           | SHIFT+(ADD w/ flags)      |             |                | C6.2.9   | RR     |
| CMN            | pseudo for ADDS           |             |                | C6.2.61  | RR     |
| SUB            | ADD                       |             |                | C6.2.357 | RI     |
| SUBS           | SHIFT+(ADD w/ flags)      |             |                | C6.2.364 | RR     |
| CMP            | pseudo for SUBS           |             |                | C6.2.64  | RR     |
| MVN            | pseudo for ORN            |             |                | C6.2.233 | RR     |
| ORN            | SHIFT+(XOR w/ 1)+OR       |             |                | C6.2.239 | RR     |
| ORR            | SHIFT+OR                  |             |                | C6.2.241 | RR     |
| EOR            | SHIFT+XOR                 |             |                | C6.2.120 | RR     |
| ANDS           | SHIFT+(AND w/ flags)      |             |                | C6.2.15  | RR     |
| TST            | pseudo for ANDS           |             |                | C6.2.383 | RR     |
| LSL            | pseudo for UBFM           |             |                | C6.2.213 | RI     |
| LSL            | pseudo for LSLV           |             |                | C6.2.212 | RR     |
| LSR            | pseudo for UBFM           |             |                | C6.2.216 | RI     |
| LSR            | pseudo for LSRV           |             |                | C6.2.215 | RR     |
| UBFM           | LSL or LSR [in decode]    |             |                | C6.2.385 | RI     |
| SBFM           | ASR                       |             |                | C6.2.268 | RI     |
| LSLV           | LSL                       |             |                | C6.2.214 | RR     |
| LSRV           | LSR                       |             |                | C6.2.217 | RR     |
| ASRV           | ASR                       |             |                | C6.2.18  | RR     |
| ASR            | pseudo for ASRV           |             |                | C6.2.16  | RR     |
| ASR            | pseudo for SBFM           |             |                | C6.2.17  | RI     |
|----------------|---------------------------|-------------|----------------|----------|--------|
| B              | ADD                       |             | Control flow   | C6.2.25  | B1     |
| B.cond         | COND_CHECK & ADD          |             |                | C6.2.26  | B2     |
| BL             | ADD & ADD                 |             |                | C6.2.34  | B1     |
| RET            | OR w/ XZR                 |             |                | C6.2.254 | B3     |
|----------------|---------------------------|-------------|----------------|----------|--------|
| NOP            | n/a                       |             | Stalling       | C6.2.238 | S      |
|----------------|---------------------------|-------------|----------------|----------|--------|
| ERET           | (OR w/ XZR) & (OR w/ XZR) | Yes         | EL1 Cconfig    | C6.2.121 | B3     |
| MRS            | OR w/ XZR                 | Yes         |                | C6.2.228 | S      |
| MSR            | OR w/ XZR                 | Yes         |                | C6.2.230 | S      |
| SVC [ EC only] | OR w/ XZR                 | Yes         |                | C6.2.365 | I1     |
|----------------|---------------------------|-------------|----------------|----------|--------|
| LDUR           | AGU+RD                    | Yes         | Floating-Point | C7.2.194 | M      |
| STUR           | AGU+WR                    | Yes         |                | C7.2.333 | M      |
| FMOV           | OR w/ XZR                 |             |                | C7.2.130 | RR     |
| FNEG           | XOR                       |             |                | C7.2.140 | RR     |
| FADD           | NAN_CHECK+FADD            |             |                | C7.2.50  | RR     |
| FMUL           | NAN_CHECK+FMUL            |             |                | C7.2.136 | RR     |
| FSUB           | NAN_CHECK+XOR+FADD        |             |                | C7.2.174 | RR     |
| FCMP           | NAN_CHECK+(ADD w/ flags)  | Yes         |                | C7.2.66  | RR     |
|----------------|---------------------------|-------------|----------------|----------|--------|

## Extras

- 30 pts: make your frontend 2-way superscalar, and beef up your backend so
  that it has the capacity to handle this without stalling uselessly.
- 30 pts: Add the SVC instruction, and use a particular value to do clean
  termination, rather than using just a segfault. You should be able to
  differentiate between a segfault termination and an SVC termiantion.
  Effectively, this is implementing a sycall. Syscalls with different numbers
  should fail with a completely different error (in a different exception
  handler). `VBAR_EL1` must also be done.
- 10 pts: Make it so writing a `terminate` value to the MSR `ACTLR_EL1` causes
  the ozone processor to enter a low power state. This will be tested by
  either placing my finger on the FPGA to see if it's hot, or seeing if my core
  is being hogged by Verilator (the Verilator testing seems off).

## Submission & Grading

Please submit a zip or tar file including:
- Your SystemVerilog files
- Your entire Quartus project directory
- A brief README or Makefile that tells the teaching staff how to build and run
  your simulator and/or your build.

The test files will also be ran on an actual ARM processor.  You will be graded
on your ability to match the output of the provided testcases using the
provided tool. All architectural state is expected to match. There are no
hidden testcases. (need a custom elf loader?).

## Tips

- We are not concerned with the speeding up fetching much beyond branch
  prediction and an iTLB. You do not need to create an L1i cache.
- We only care about the valid bit on a translation block (fix name?). Don't
  worry about other flags such as execute, read-only, etc.
- All branches are speculative, and your processor must be able to handle
  mispredictions.
- We make certain guarantees about what inputs this processor will be given.
  You are encouraged to hardcode the behavior of your processor to fit only
  these use cases.
- It is likely your architectural register file will be much larger than 31 registers. Give your architectural regfile access to.
- Moving between exception levels can be done speculatively,  not be done speculatively.
- On an exception, clear out the reservation station entries, let everything
  drain from the functional units (or send a reset signal), and then flush
  everything in the ROB after the excepting instruction.
- We assume that decode will generate clean immediates.
- With NZCV, you may want two destination registers.
- A shift with an immediate, we consider to be just an immediate. The shift can
  occur in decode.
- Slightly change the input of barrelshifter so it only uses bottom 6 bits of
  register on shift.
- We assert that UBFM and SBFM will never be used other than to encode the
  immediate forms of LSL, LSR, and ASR immediate
- For the uops, + means sequencing, & means dispatch concurrently
- SPSR stores your Exception Level. ESR stores your return PC from an exception level.
- Though FLOP registers are normally 128-bit, we're only going to implement the
  64-bit values for them.
- To interface Verilator with this testing infrastructure, you're going to want
  to use shared memory. This requires using Verilator's C++ tools. An example
  of this is in the code base. You can use it like so:
  1. Build the verilator example: `cd verilator && make`
  2. Run the hardware model in one terminal: `./verilator/obj_dir/VTop`
  3. Run your program in another terminal: `./ozone ozone-config.json run_verilator testcases/bin/0_add.elf`
- Check the verilator generated header files in `obj_dir` to learn more about
  how to use this

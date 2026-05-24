# Ozone (Out-Of-Order) Processor

A single-issue out-of-order ARMv8-A processor implementing the chArm-v6 ISA (a subset of ARM A64), written in SystemVerilog. Uses Tomasulo-style scheduling with a reorder buffer for speculation and precise exceptions. Validated in Verilator and deployed to a DE10-Nano FPGA.

In the testing/ directory, first run `make` then `verilator/obj_dir/VTop` to start running ozone in Verilator, then `make test` in another terminal to iterate through all of the test cases. Original test cases are prefixed by 'stud_'.

Quartus project directory is in memory/mem_GHRD.

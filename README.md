# Ozone (Out-Of-Order) Processor

In the testing/ directory, first run `make` then `verilator/obj_dir/VTop` to start running ozone in Verilator, then `./ozone ozone-config.json check_verilator testcases/bin/{.elf testcase}`. Original test cases are prefixed by 'stud_'.

A make target has been added, `make test`, that will iterate through all of the test cases.
Just make sure that you are running `verilator/obj_dir/VTop` in another terminal.

Quartus project directory is in memory/mem_GHRD.

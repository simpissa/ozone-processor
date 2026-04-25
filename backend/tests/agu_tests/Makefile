obj_dir: clean
	verilator --binary ../../../types.sv ../../units/address_generation_unit.sv aguTb.sv
test: ./obj_dir
	g++ make_tests.cpp -o make_tests && make_tests
	obj_dir/Vtypes
clean:
	-rm make_tests
	-rm -rf ./obj_dir
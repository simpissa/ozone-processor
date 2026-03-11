clean:
	rm -r obj_dir

tlb: tlb.sv tests/tlb_tb.sv
	verilator --assert --binary tlb.sv tests/tlb_tb.sv

loadq: loadq.sv tests/loadq_tb.sv
	verilator --assert --binary loadq.sv tests/loadq_tb.sv

test-load: loadq
	obj_dir/Vloadq

test-tlb: tlb
	obj_dir/Vtlb

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

top: tlb.sv l1cache.sv l2.sv storeq.sv loadq.sv mem_top.sv
	verilator --assert --binary --top-module mem_top \
	mem_top.sv loadq.sv storeq.sv l2.sv l1cache.sv tlb.sv

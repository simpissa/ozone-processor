clean:
	rm -r obj_dir

tlb: tlb.sv tests/tlb_tb.sv
	verilator --assert --binary tlb.sv tests/tlb_tb.sv

loadq: loadq.sv tests/loadq_tb.sv
	verilator --assert --binary loadq.sv tests/loadq_tb.sv

l1cache: l1cache.sv tests/l1cache_tb.sv
	verilator --assert --binary l1cache.sv tests/l1cache_tb.sv

test-load: loadq
	obj_dir/Vloadq

test-tlb: tlb
	obj_dir/Vtlb

test-l1: l1cache
	obj_dir/Vl1cache

top: tlb.sv l1cache.sv l2.sv storeq.sv loadq.sv mem_top.sv
	verilator --assert --binary --top-module mem_top \
	mem_top.sv loadq.sv storeq.sv l2.sv l1cache.sv tlb.sv

test-top: mem_tb.sv mem_top.sv loadq.sv storeq.sv l2.sv l1cache.sv tlb.sv
	verilator --assert --binary --top-module mem_tb \
	mem_tb.sv mem_top.sv loadq.sv storeq.sv l2.sv l1cache.sv tlb.sv
	obj_dir/Vmem_tb +TRACE_FILE=mem-traces-v2/traces/dgemm3_lsq88.bin


    

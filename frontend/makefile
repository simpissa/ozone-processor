clean:
	rm -r obj_dir 

fetch: fetch.sv tests/fetch_tb.sv
	verilator --binary --assert fetch.sv
	verilator --binary --assert tests/fetch_tb.sv fetch.sv
test-fetch: fetch
	obj_dir/Vfetch_tb

debug-fetch: fetch
	obj_dir/Vfetch_tb +FDEBUG=1
	
	
    

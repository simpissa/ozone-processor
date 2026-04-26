clean:
	rm -r obj_dir 

fetch: fetch.sv tests/fetch_tb.sv
	verilator --binary --assert tests/fetch_tb.sv fetch.sv
test-fetch: fetch
	obj_dir/Vfetch_tb

debug-fetch: fetch
	obj_dir/Vfetch_tb +FDEBUG=1

itlb: itlb.sv tests/itlb_tb.sv
	verilator --binary --assert tests/itlb_tb.sv itlb.sv

test-itlb: itlb
	obj_dir/Vitlb_tb

debug-itlb: itlb
	obj_dir/Vitlb_tb +IDEBUG=1

frontend: ../types.sv frontend.sv fetch.sv tests/frontendTb.sv
	verilator --binary --assert --top-module frontendTb --Wno-CASEWITHX --Wno-CASEINCOMPLETE --Wno-WIDTHEXPAND ../types.sv tests/frontendTb.sv frontend.sv fetch.sv

test-frontend: frontend
	obj_dir/VfrontendTb

	
    

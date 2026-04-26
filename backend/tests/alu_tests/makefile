alu: ./../../units/alu.sv ./aluTest.sv
	clear
	verilator --assert --binary ../../../types.sv ./../../units/alu.sv ./aluTest.sv
	./obj_dir/Vtypes

clean:
	rm -r obj_dir
    

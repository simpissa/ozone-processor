VERILATOR ?= verilator
INCLUDES = -I../fpu/src -I../fpu/src/common_cells/include
COMMON_CELLS = \
	../fpu/src/common_cells/src/cf_math_pkg.sv \
	../fpu/src/common_cells/src/lzc.sv \
	../fpu/src/common_cells/src/rr_arb_tree.sv
FPU_SRC := $(shell grep -E '^[[:space:]]*(src/|vendor/)' ../fpu/src_files.yml | sed 's/^[[:space:]]*//;s/,//;s#^#../fpu/#' )
VERILATOR_SUPPRESS = --Wno-WIDTHEXPAND --Wno-WIDTHTRUNC --Wno-ASCRANGE --Wno-MULTITOP --Wno-UNOPTFLAT --Wno-STMTDLY --Wno-UNSIGNED

clean:
	rm -rf obj_dir

backend: ../types.sv $(COMMON_CELLS) $(FPU_SRC) backend.sv units/fpuExec.sv
	$(VERILATOR) --binary --assert --top-module backendTb $(INCLUDES) $(VERILATOR_SUPPRESS) ../types.sv $(COMMON_CELLS) $(FPU_SRC) backend.sv units/fpuExec.sv

test-backend: backend
	obj_dir/VbackendTb

FPU_PKG := ../../../fpu/src/fpnew_pkg.sv
FPU_SRCS := $(shell find ../../../fpu/src -maxdepth 1 -name '*.sv' ! -name 'fpnew_pkg.sv' | sort)
COMMON_CELLS_PKGS := ../../../fpu/src/common_cells/src/cf_math_pkg.sv ../../../fpu/src/common_cells/src/ecc_pkg.sv
COMMON_CELLS_SRCS := $(shell find ../../../fpu/src/common_cells/src -name '*.sv' ! -name 'cf_math_pkg.sv' ! -name 'ecc_pkg.sv' | sort)
OPENE906_SRCS := $(shell find ../../../fpu/vendor/opene906 -name '*.v' | sort)
OPENC910_SRCS := $(shell find ../../../fpu/vendor/openc910 -name '*.v' | sort)

obj_dir: clean
	verilator --binary --top-module fpuExecTb \
		-Wno-fatal \
		-I../../../fpu/src \
		-I../../../fpu/src/common_cells/include \
		../../../types.sv \
		$(FPU_PKG) \
		$(FPU_SRCS) \
		$(COMMON_CELLS_PKGS) \
		$(COMMON_CELLS_SRCS) \
		$(OPENE906_SRCS) \
		$(OPENC910_SRCS) \
		../../units/fpuExec.sv \
		fpuExecTb.sv

test: ./obj_dir
	g++ makeTests.cpp -o makeTests && ./makeTests
	obj_dir/VfpuExecTb

clean:
	-rm -f makeTests
	-rm -rf ./obj_dir

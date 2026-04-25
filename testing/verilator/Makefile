VERILATOR = verilator

ROOT     = ../..
FPU_DIR  = $(ROOT)/fpu
COMMON   = $(FPU_DIR)/src/common_cells

FPU_PKG          := $(FPU_DIR)/src/fpnew_pkg.sv
FPU_SRCS         := $(shell find $(FPU_DIR)/src -maxdepth 1 -name '*.sv' ! -name 'fpnew_pkg.sv' | sort)
COMMON_CELLS_PKG := $(COMMON)/src/cf_math_pkg.sv $(COMMON)/src/ecc_pkg.sv
COMMON_CELLS     := $(shell find $(COMMON)/src -name '*.sv' ! -name 'cf_math_pkg.sv' ! -name 'ecc_pkg.sv' | sort)
OPENE906         := $(shell find $(FPU_DIR)/vendor/opene906 -name '*.v' | sort)
OPENC910         := $(shell find $(FPU_DIR)/vendor/openc910 -name '*.v' | sort)

CORE_SRCS = \
    $(ROOT)/types.sv \
    $(ROOT)/proc.sv \
    $(ROOT)/frontend/branchPredictor.sv \
    $(ROOT)/frontend/decoder.sv \
    $(ROOT)/frontend/itlb.sv \
    $(ROOT)/frontend/fetch.sv \
    $(ROOT)/frontend/frontend.sv \
    $(ROOT)/backend/units/alu.sv \
    $(ROOT)/backend/units/shifter_unit.sv \
    $(ROOT)/backend/units/logic_unit.sv \
    $(ROOT)/backend/units/address_generation_unit.sv \
    $(ROOT)/backend/units/fpuExec.sv \
    $(ROOT)/backend/cdb.sv \
    $(ROOT)/backend/issue.sv \
    $(ROOT)/backend/rename.sv \
    $(ROOT)/backend/rob.sv \
    $(ROOT)/backend/backend.sv \
    $(ROOT)/backend/core_backend.sv \
    $(ROOT)/memory/loadq.sv \
    $(ROOT)/memory/storeq.sv

V_FLAGS = -Wno-fatal --cc --exe --build -j --top-module Top \
          -I$(FPU_DIR)/src -I$(COMMON)/include

all: obj_dir/VTop

obj_dir/VTop: Top.sv sim_main.cpp $(CORE_SRCS)
	$(VERILATOR) $(V_FLAGS) \
	    $(FPU_PKG) $(FPU_SRCS) \
	    $(COMMON_CELLS_PKG) $(COMMON_CELLS) \
	    $(OPENE906) $(OPENC910) \
	    $(CORE_SRCS) \
	    Top.sv sim_main.cpp \
	    -o VTop -LDFLAGS "-lrt"

clean:
	rm -rf obj_dir

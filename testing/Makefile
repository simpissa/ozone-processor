EXEC=ozone
DEBUG_FLAGS=-g3

CAPSTONE_DIR=capstone
CAPSTONE_LIB=$(CAPSTONE_DIR)/libcapstone.a
CAPSTONE_INC=$(CAPSTONE_DIR)/include

TEST_SRC_DIR=testcases/src
TEST_BIN_DIR=testcases/bin

BASE_TEST_SRCS=$(wildcard $(TEST_SRC_DIR)/[012]_*.s) $(TEST_SRC_DIR)/3_page_fault.s
STANDALONE_BINS=$(patsubst $(TEST_SRC_DIR)/%.s, $(TEST_BIN_DIR)/%.elf, $(BASE_TEST_SRCS))
EL1_BINS=$(patsubst $(TEST_SRC_DIR)/%.s, $(TEST_BIN_DIR)/el1_%.elf, $(BASE_TEST_SRCS))

# STUDENTS: change the below based on what your ARM compiler's prefixes are. It
# may have no prefix.
CROSS_COMPILE=aarch64-linux-gnu-
GCC=$(CROSS_COMPILE)gcc

.PHONY: all clean tests verify

all: $(EXEC) tests

$(EXEC): src/log.c src/ozone_config.c src/sim.c src/run.c src/main.c $(CAPSTONE_LIB)
	gcc $(DEBUG_FLAGS) -I inc -I $(CAPSTONE_INC) -o $@ $^

$(CAPSTONE_LIB):
	cd $(CAPSTONE_DIR) && CAPSTONE_ARCHS="aarch64" ./make.sh

tests: $(EXEC) $(STANDALONE_BINS) $(EL1_BINS)

# Confirm that our bummy simulator produces the same architectural state as QEMU
verify: tests
	@for elf in $(TEST_BIN_DIR)/*.elf; do \
		./verify.py $$elf || exit 1; \
	done

# Compile bootloader object
$(TEST_BIN_DIR)/boot.o: $(TEST_SRC_DIR)/boot.s
	mkdir -p $(TEST_BIN_DIR)
	$(GCC) -c -o $@ $<

# Compile standalone start shim
$(TEST_BIN_DIR)/standalone_start.o: $(TEST_SRC_DIR)/standalone_start.s
	mkdir -p $(TEST_BIN_DIR)
	$(GCC) -c -o $@ $<

# Rule for el1_*.elf (EL1-enabled tests)
$(TEST_BIN_DIR)/el1_%.elf: $(TEST_SRC_DIR)/%.s $(TEST_BIN_DIR)/boot.o linker.ld
	$(GCC) -nostdlib -static -T linker.ld -o $@ $< $(TEST_BIN_DIR)/boot.o

# Rule for standalone ELFs (using shim)
$(TEST_BIN_DIR)/%.elf: $(TEST_SRC_DIR)/%.s $(TEST_BIN_DIR)/standalone_start.o linker.ld
	$(GCC) -nostdlib -static -T linker.ld -o $@ $< $(TEST_BIN_DIR)/standalone_start.o

linker.ld: $(EXEC) ozone-config.json
	./$(EXEC) ozone-config.json gen_linker_script

clean:
	$(RM) $(EXEC) linker.ld ozone.zip
	$(RM) -rf $(TEST_BIN_DIR)

ozone.zip: clean
	make -C verilator clean
	zip -r ozone.zip capstone/ inc/ src/ testcases/ verilator/ Makefile ozone-config.json README.md verify.py

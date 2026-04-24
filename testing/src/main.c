#include "ozone_config.h"
#include "log.h"
#include "sim.h"
#include "run.h"
#include <stdalign.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>

typedef uint64_t address_t;
typedef char* dram_t;

static void print_usage(const char * const program_name) {
  printf(
    "Usage: %s CONFIG_FILE SUBCOMMAND [ARGS] [OPTIONS]\n"
    "SUBCOMMANDS\n"
    "    run AARCH64_BINARY\n"
    "        runs the specified test case on the FPGA\n"
    "    run_verilator AARCH64_BINARY\n"
    "        runs the specified test case using Verilator shared memory\n"
    "    sim AARCH64_BINARY\n"
    "        simulate the program using a basic one instruction at-a-time\n"
    "        software simulator\n"
    "    check AARCH64_BINARY\n"
    "        compares simulator and FPGA results\n"
    "    gen_linker_script\n"
    "        creates a linker script based on the config file. AArch64\n"
    "        binaries should be regenerated after this is done.\n"
    "OPTIONS\n"
    "    -l, --log-level LEVEL\n"
    "        set the logging level (DEBUG, INFO, ERROR). Default is INFO.\n"
    ,
    program_name
  );
}

static int compare_states(cpu_state_t* sim, cpu_state_t* fpga) {
    int mismatches = 0;
    plog(LOG_INFO, "\n--- Comparing Architectural States ---\n");

    // General Purpose Registers
    for (int i = 0; i < 31; i++) {
        if (sim->x[i] != fpga->x[i]) {
            plog(LOG_ERROR, "Mismatch X%d: SIM=0x%016lx FPGA=0x%016lx\n", i, sim->x[i], fpga->x[i]);
            mismatches++;
        }
    }

    // Floating Point Registers
    for (int i = 0; i < 32; i++) {
        if (sim->v[i] != fpga->v[i]) {
            plog(LOG_ERROR, "Mismatch V%d: SIM=0x%016lx FPGA=0x%016lx\n", i, sim->v[i], fpga->v[i]);
            mismatches++;
        }
    }

    // System Registers
    if (sim->pc != fpga->pc) { plog(LOG_ERROR, "Mismatch PC: SIM=0x%016lx FPGA=0x%016lx\n", sim->pc, fpga->pc); mismatches++; }
    if (sim->pstate != fpga->pstate) { plog(LOG_ERROR, "Mismatch PSTATE: SIM=0x%08x FPGA=0x%08x\n", sim->pstate, fpga->pstate); mismatches++; }
    if (sim->sp_el0 != fpga->sp_el0) { plog(LOG_ERROR, "Mismatch SP_EL0: SIM=0x%016lx FPGA=0x%016lx\n", sim->sp_el0, fpga->sp_el0); mismatches++; }
    if (sim->sp_el1 != fpga->sp_el1) { plog(LOG_ERROR, "Mismatch SP_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->sp_el1, fpga->sp_el1); mismatches++; }
    if (sim->spsr_el1 != fpga->spsr_el1) { plog(LOG_ERROR, "Mismatch SPSR_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->spsr_el1, fpga->spsr_el1); mismatches++; }
    if (sim->elr_el1 != fpga->elr_el1) { plog(LOG_ERROR, "Mismatch ELR_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->elr_el1, fpga->elr_el1); mismatches++; }
    if (sim->esr_el1 != fpga->esr_el1) { plog(LOG_ERROR, "Mismatch ESR_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->esr_el1, fpga->esr_el1); mismatches++; }
    if (sim->ttbr0_el1 != fpga->ttbr0_el1) { plog(LOG_ERROR, "Mismatch TTBR0_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->ttbr0_el1, fpga->ttbr0_el1); mismatches++; }
    if (sim->vbar_el1 != fpga->vbar_el1) { plog(LOG_ERROR, "Mismatch VBAR_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->vbar_el1, fpga->vbar_el1); mismatches++; }
    if (sim->actlr_el1 != fpga->actlr_el1) { plog(LOG_ERROR, "Mismatch ACTLR_EL1: SIM=0x%016lx FPGA=0x%016lx\n", sim->actlr_el1, fpga->actlr_el1); mismatches++; }

    // Memory comparison
    for (uint64_t i = 0; i < DRAM_SIZE; i += 8) {
        bool word_mod = false;
        for (int j = 0; j < 8; j++) if (sim->modified_bitmap[(i + j) / 8] & (1 << ((i + j) % 8))) { word_mod = true; break; }
        if (word_mod) {
            uint64_t s_val, f_val;
            memcpy(&s_val, &sim->dram[i], 8);
            memcpy(&f_val, &fpga->dram[i], 8);
            if (s_val != f_val) {
                plog(LOG_ERROR, "Memory Mismatch at 0x%016lx: SIM=0x%016lx FPGA=0x%016lx\n", sim->dram_base + i, s_val, f_val);
                mismatches++;
            }
        }
    }

    if (mismatches == 0) {
        plog(LOG_INFO, "✅ SUCCESS: All architectural state matches!\n");
    } else {
        plog(LOG_ERROR, "❌ FAILURE: %d mismatches found.\n", mismatches);
    }
    return mismatches;
}

int main(int argc, char* argv[]) {
  if (argc < 3) {
    print_usage(argv[0]);
    return -1;
  }

  const char* config_path = argv[1];
  const char* subcommand = argv[2];
  int arg_idx = 3;

  log_priority_e priority = LOG_INFO;

  for (int i = 1; i < argc; i++) {
    if ((strcmp(argv[i], "-l") == 0 || strcmp(argv[i], "--log-level") == 0) && i + 1 < argc) {
      if (strcasecmp(argv[i+1], "DEBUG") == 0) priority = LOG_DEBUG;
      else if (strcasecmp(argv[i+1], "INFO") == 0) priority = LOG_INFO;
      else if (strcasecmp(argv[i+1], "ERROR") == 0) priority = LOG_ERROR;
    }
  }

  log_set_global_priority(priority);
  ozone_config_t config;
  ozone_config_read(&config, config_path);

  if (strcmp(subcommand, "sim") == 0) {
    if (arg_idx >= argc) { print_usage(argv[0]); return -1; }
    const char* const binary_path = argv[arg_idx];
    cpu_state_t cpu;
    sim_init(&cpu, &config);
    sim_run(&cpu, binary_path);
    sim_print_state(&cpu);
    sim_destroy(&cpu);
  } else if (strcmp(subcommand, "run") == 0) {
    if (arg_idx >= argc) { print_usage(argv[0]); return -1; }
    const char* const binary_path = argv[arg_idx];
    fpga_run(&config, binary_path);
  } else if (strcmp(subcommand, "run_verilator") == 0) {
    if (arg_idx >= argc) { print_usage(argv[0]); return -1; }
    const char* const binary_path = argv[arg_idx];
    verilator_run(&config, binary_path);
  } else if (strcmp(subcommand, "check") == 0) {
    if (arg_idx >= argc) { print_usage(argv[0]); return -1; }
    const char* const binary_path = argv[arg_idx];
    
    plog(LOG_INFO, "Step 1: Simulating behavior...\n");
    cpu_state_t sim_cpu;
    sim_init(&sim_cpu, &config);
    sim_run(&sim_cpu, binary_path);

    plog(LOG_INFO, "Step 2: Running on FPGA...\n");
    fpga_run(&config, binary_path);
    
    cpu_state_t fpga_cpu;
    sim_init(&fpga_cpu, &config);
    fpga_get_state(&fpga_cpu);

    compare_states(&sim_cpu, &fpga_cpu);

    sim_destroy(&sim_cpu);
    sim_destroy(&fpga_cpu);
  } else if (strcmp(subcommand, "gen_linker_script") == 0) {
    FILE* f = fopen("linker.ld", "w");
    if (!f) {
        plog(LOG_ERROR, "Couldn't open linker.ld for writing\n");
        return -1;
    }
    fprintf(f, "ENTRY(start)\n");
    fprintf(f, "SECTIONS {\n");
    fprintf(f, "  . = 0x%lx;\n", config.reset_vector);
    fprintf(f, "  .text.boot : { *(.text.boot) }\n");
    fprintf(f, "  .exception_vectors : { \n");
    fprintf(f, "    . = ALIGN(2048);\n");
    fprintf(f, "    *(.exception_vectors)\n");
    fprintf(f, "  }\n");
    
    fprintf(f, "  .config_data : { \n");
    fprintf(f, "    . = ALIGN(8);\n");
    fprintf(f, "    _CONFIG_START = .;\n");
    fprintf(f, "    QUAD(0x%lx); /* _SP_EL0 */\n", config.sp_el0);
    fprintf(f, "    QUAD(0x%lx); /* _SP_EL1 */\n", config.sp_el1);
    fprintf(f, "    QUAD(0x%lx); /* _VBAR_EL1 */\n", config.vbar_el1);
    fprintf(f, "    QUAD(0x%lx); /* _SPSR_EL1 */\n", config.spsr_el1);
    fprintf(f, "    QUAD(0x%lx); /* _ELR_EL1 */\n", config.elr_el1);
    fprintf(f, "    QUAD(0x%lx); /* _TTBR0_EL1 */\n", config.ttbr0);
    fprintf(f, "    QUAD(0x%lx); /* _TERMINATE_VAL */\n", config.terminate_val);
    fprintf(f, "    QUAD(0x%lx); /* _NUM_STACK_PAGES */\n", config.num_stack_pages);
    fprintf(f, "  }\n");

    fprintf(f, "  . = 0x%lx;\n", config.entry);
    fprintf(f, "  .text : { *(.text) }\n");
    fprintf(f, "  .data : { *(.data) }\n");
    fprintf(f, "  .bss : { *(.bss) }\n");
    fprintf(f, "}\n");
    fclose(f);
    plog(LOG_INFO, "Generated linker.ld\n");
  } else {
    plog(LOG_ERROR, "Unknown subcommand: %s\n", subcommand);
    return -1;
  }

  return 0;
}

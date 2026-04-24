#ifndef SIM_H
#define SIM_H

#include <stdint.h>
#include <stdbool.h>
#include "ozone_config.h"

#define NUM_X_REGS 31
#define DRAM_SIZE (1024ULL * 1024 * 1024) // 1 GB DRAM

typedef struct {
    uint64_t x[NUM_X_REGS];
    uint64_t v[32]; // Floating point registers (64-bit only)
    uint64_t sp;
    uint64_t pc;
    uint32_t pstate; // N, Z, C, V (bits 31, 30, 29, 28)
    
    // System Registers
    uint64_t spsr_el1;
    uint64_t elr_el1;
    uint64_t esr_el1;
    uint64_t sp_el0;
    uint64_t sp_el1;
    uint64_t ttbr0_el1;
    uint64_t vbar_el1;
    uint64_t actlr_el1;
    
    uint8_t el; // 0 or 1
    
    uint8_t* dram;
    uint64_t dram_base;
    uint64_t entry;
    uint64_t terminate_val;
    uint8_t* modified_bitmap;
    
    bool terminated;
} cpu_state_t;

void sim_init(cpu_state_t* cpu, ozone_config_t* config);
void sim_run(cpu_state_t* cpu, const char* binary_path);
void sim_print_state(cpu_state_t* cpu);
void sim_destroy(cpu_state_t* cpu);

#endif // SIM_H

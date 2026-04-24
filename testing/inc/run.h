#ifndef RUN_H
#define RUN_H

#include "ozone_config.h"

#include "sim.h"

void fpga_run(ozone_config_t* config, const char* binary_path);
void fpga_get_state(cpu_state_t* cpu);

void verilator_run(ozone_config_t* config, const char* binary_path);
void verilator_get_state(cpu_state_t* cpu);

#endif // RUN_H

#ifndef OZONE_CONFIG_H
#define OZONE_CONFIG_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
	uint64_t reset_vector;
	uint64_t entry;
	uint64_t ttbr0;
	uint64_t terminate_val;
	uint64_t sp_el0;
	uint64_t sp_el1;
	uint64_t vbar_el1;
	uint64_t spsr_el1;
	uint64_t elr_el1;
	uint64_t num_stack_pages;
} ozone_config_t;

void ozone_config_read(ozone_config_t* config, const char * const config_path);
void ozone_config_print(ozone_config_t* config);

#endif // OZONE_CONFIG_H

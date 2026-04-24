#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <elf.h>
#include <inttypes.h>
#include "run.h"
#include "log.h"

// DE10-Nano standard addresses
#define HPS2FPGA_AXI_BASE 0xC0000000ULL
#define HPS2FPGA_AXI_SPAN 0x40000000ULL // 1GB

#define LWHPS2FPGA_AXI_BASE 0xFF200000ULL
#define LWHPS2FPGA_AXI_SPAN 0x00200000ULL // 2MB

// CSR Offsets
#define CSR_RESET_REG    0x0
#define CSR_STATUS_REG   0x8
#define CSR_DONE_BIT     (1 << 0)

// Register Mapping in CSR
#define CSR_X_REGS_BASE  0x100
#define CSR_PC           0x200
#define CSR_PSTATE       0x208
#define CSR_SP_EL0       0x210
#define CSR_SP_EL1       0x218
#define CSR_SPSR_EL1     0x220
#define CSR_ELR_EL1      0x228
#define CSR_ESR_EL1      0x230
#define CSR_TTBR0_EL1    0x238
#define CSR_VBAR_EL1     0x240
#define CSR_ACTLR_EL1    0x248
#define CSR_V_REGS_BASE  0x300

static void* g_dram_ptr = NULL;
static void* g_csr_ptr = NULL;

static void common_load_and_run(const char* binary_path) {
    if (!g_dram_ptr || !g_csr_ptr) return;

    // 1. Load ELF into SDRAM
    FILE* f = fopen(binary_path, "rb");
    if (!f) {
        plog(LOG_ERROR, "Couldn't open ELF: %s\n", binary_path);
        return;
    }

    Elf64_Ehdr ehdr;
    if (fread(&ehdr, 1, sizeof(ehdr), f) != sizeof(ehdr)) {
        plog(LOG_ERROR, "Failed to read ELF header\n");
        fclose(f);
        return;
    }

    fseek(f, (long)ehdr.e_phoff, SEEK_SET);
    Elf64_Phdr phdr;
    for (int i = 0; i < (int)ehdr.e_phnum; i++) {
        if (fread(&phdr, 1, sizeof(phdr), f) != sizeof(phdr)) {
            plog(LOG_ERROR, "Failed to read program header %d\n", i);
            break;
        }

        if (phdr.p_type == PT_LOAD) {
            long current_pos = ftell(f);
            fseek(f, (long)phdr.p_offset, SEEK_SET);
            
            if (phdr.p_paddr + phdr.p_memsz > HPS2FPGA_AXI_SPAN) {
                plog(LOG_ERROR, "Segment %d (PA 0x%"PRIx64") out of bridge span\n", i, phdr.p_paddr);
                continue;
            }

            void* target = (uint8_t*)g_dram_ptr + phdr.p_paddr;
            if (fread(target, 1, phdr.p_filesz, f) != phdr.p_filesz) {
                plog(LOG_ERROR, "Failed to write segment %d to memory\n", i);
            }
            if (phdr.p_memsz > phdr.p_filesz) {
                memset((uint8_t*)target + phdr.p_filesz, 0, phdr.p_memsz - phdr.p_filesz);
            }
            plog(LOG_INFO, "Loaded segment %d at PA 0x%"PRIx64" (0x%"PRIx64" bytes)\n", i, phdr.p_paddr, phdr.p_memsz);
            fseek(f, current_pos, SEEK_SET);
        }
    }
    fclose(f);

    // 2. Reset the Ozone Processor
    plog(LOG_INFO, "Resetting Ozone Processor...\n");
    volatile uint32_t* reset_reg = (volatile uint32_t*)((uint8_t*)g_csr_ptr + CSR_RESET_REG);
    *reset_reg = 1;  // Assert reset
    usleep(1000);    // Wait 1ms
    *reset_reg = 0;  // Deassert reset

    // 3. Poll for completion
    plog(LOG_INFO, "Processor running. Polling for completion signal...\n");
    volatile uint32_t* status_reg = (volatile uint32_t*)((uint8_t*)g_csr_ptr + CSR_STATUS_REG);
    
    while (!(*status_reg & CSR_DONE_BIT)) {
        usleep(10000); // 10ms poll interval
    }

    plog(LOG_INFO, "Processor signaled completion!\n");
}

static void* map_bridge(int fd, uint64_t base, uint64_t span) {
    void* ptr = mmap(NULL, span, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    if (ptr == MAP_FAILED) {
        plog(LOG_ERROR, "Failed to mmap bridge at 0x%"PRIx64"\n", base);
        return NULL;
    }
    return ptr;
}

void fpga_run(ozone_config_t* config, const char* binary_path) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        plog(LOG_ERROR, "Failed to open /dev/mem. Are you root?\n");
        return;
    }

    g_dram_ptr = map_bridge(fd, HPS2FPGA_AXI_BASE, HPS2FPGA_AXI_SPAN);
    g_csr_ptr = map_bridge(fd, LWHPS2FPGA_AXI_BASE, LWHPS2FPGA_AXI_SPAN);

    if (g_dram_ptr && g_csr_ptr) {
        plog(LOG_INFO, "Mapped FPGA bridges\n");
        common_load_and_run(binary_path);
    }

    if (g_dram_ptr) munmap(g_dram_ptr, HPS2FPGA_AXI_SPAN);
    if (g_csr_ptr) munmap(g_csr_ptr, LWHPS2FPGA_AXI_SPAN);
    close(fd);
}

void verilator_run(ozone_config_t* config, const char* binary_path) {
    // Verilator assumes bridges are exposed via shared memory files in /dev/shm
    int dram_fd = shm_open("/ozone_dram", O_RDWR, 0666);
    int csr_fd = shm_open("/ozone_csr", O_RDWR, 0666);

    if (dram_fd < 0 || csr_fd < 0) {
        plog(LOG_ERROR, "Failed to open Verilator shared memory bridges. Is the Verilator program running?\n");
        if (dram_fd >= 0) close(dram_fd);
        if (csr_fd >= 0) close(csr_fd);
        return;
    }

    g_dram_ptr = mmap(NULL, HPS2FPGA_AXI_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, dram_fd, 0);
    g_csr_ptr = mmap(NULL, LWHPS2FPGA_AXI_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, csr_fd, 0);

    if (g_dram_ptr != MAP_FAILED && g_csr_ptr != MAP_FAILED) {
        plog(LOG_INFO, "Mapped Verilator bridges\n");
        common_load_and_run(binary_path);
    } else {
        plog(LOG_ERROR, "Failed to mmap Verilator bridges\n");
    }

    if (g_dram_ptr != MAP_FAILED) munmap(g_dram_ptr, HPS2FPGA_AXI_SPAN);
    if (g_csr_ptr != MAP_FAILED) munmap(g_csr_ptr, LWHPS2FPGA_AXI_SPAN);
    close(dram_fd);
    close(csr_fd);
}

void fpga_get_state(cpu_state_t* cpu) {
    if (!g_csr_ptr || !g_dram_ptr) return;

    for (int i = 0; i < 31; i++) {
        cpu->x[i] = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_X_REGS_BASE + (i * 8));
    }
    for (int i = 0; i < 32; i++) {
        cpu->v[i] = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_V_REGS_BASE + (i * 8));
    }
    cpu->pc = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_PC);
    cpu->pstate = *(volatile uint32_t*)((uint8_t*)g_csr_ptr + CSR_PSTATE);
    cpu->sp_el0 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_SP_EL0);
    cpu->sp_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_SP_EL1);
    cpu->spsr_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_SPSR_EL1);
    cpu->elr_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_ELR_EL1);
    cpu->esr_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_ESR_EL1);
    cpu->ttbr0_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_TTBR0_EL1);
    cpu->vbar_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_VBAR_EL1);
    cpu->actlr_el1 = *(volatile uint64_t*)((uint8_t*)g_csr_ptr + CSR_ACTLR_EL1);

    memcpy(cpu->dram, g_dram_ptr, DRAM_SIZE);
}

void verilator_get_state(cpu_state_t* cpu) {
    // Current implementation uses same CSR mapping for both
    fpga_get_state(cpu);
}

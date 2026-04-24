#include <verilated.h>
#include "VTop.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <iostream>

#define DRAM_SPAN 0x40000000ULL // 1GB
#define CSR_SPAN  0x00200000ULL // 2MB

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VTop* top = new VTop;

    // 1. Setup Shared Memory
    shm_unlink("/ozone_dram");
    shm_unlink("/ozone_csr");

    int dram_fd = shm_open("/ozone_dram", O_CREAT | O_RDWR, 0666);
    int csr_fd  = shm_open("/ozone_csr",  O_CREAT | O_RDWR, 0666);

    ftruncate(dram_fd, DRAM_SPAN);
    ftruncate(csr_fd,  CSR_SPAN);

    uint8_t* dram_shm = (uint8_t*)mmap(NULL, DRAM_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, dram_fd, 0);
    uint8_t* csr_shm  = (uint8_t*)mmap(NULL, CSR_SPAN,  PROT_READ | PROT_WRITE, MAP_SHARED, csr_fd, 0);

    memset(csr_shm, 0, CSR_SPAN);

    std::cout << "[Verilator] Shared memory initialized. Waiting for reset..." << std::endl;

    bool last_reset = false;

    while (!Verilated::gotFinish()) {
        // Toggle clock
        top->clk = 0; top->eval();
        top->clk = 1;

        // Sync Reset from SHM (Offset 0x0)
        top->reset = *(volatile uint32_t*)(csr_shm + 0x0);
        
        if (top->reset && !last_reset) {
            std::cout << "[Verilator] Reset asserted by Host." << std::endl;
        }
        last_reset = top->reset;

        // Handle Memory Read
        if (top->mem_en) {
            if (top->mem_addr < DRAM_SPAN) {
                top->mem_rdata = *(uint32_t*)(&dram_shm[top->mem_addr]);
            }
        }

        top->eval();

        // Sync State to SHM
        // Status (Offset 0x8)
        *(volatile uint32_t*)(csr_shm + 0x8) = (uint32_t)top->done;

        // X Registers (Offset 0x100)
        for (int i = 0; i < 31; i++) {
            *(volatile uint64_t*)(csr_shm + 0x100 + (i * 8)) = top->x_regs[i];
        }

        if (top->done) {
            std::cout << "[Verilator] Execution complete. X0=" << std::hex << top->x_regs[0] << std::endl;
            // Wait for reset to be cleared before allowing another run
            while (*(volatile uint32_t*)(csr_shm + 0x0)) { usleep(1000); }
            top->done = 0; // Reset for next potential run
        }

        usleep(100); // Slow down simulation for visibility
    }

    delete top;
    return 0;
}

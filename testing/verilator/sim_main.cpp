#include <verilated.h>
#include "VTop.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <iostream>

#define DRAM_SPAN 0x40000000ULL // 1GB
#define CSR_SPAN  0x00200000ULL // 2MB

// CSR layout — must match testing/src/run.c.
#define CSR_RESET_REG    0x0
#define CSR_STATUS_REG   0x8
#define CSR_DONE_BIT     (1u << 0)
#define CSR_START_PC     0x10
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

// Indices into Top's sprf[0:7] — must match spr_t in types.sv.
enum {
    SPR_SP_EL0 = 0,
    SPR_SP_EL1 = 1,
    SPR_ELR_EL1 = 2,
    SPR_SPSR_EL1 = 3,
    SPR_ESR_EL1 = 4,
    SPR_TTBR0_EL1 = 5,
    SPR_VBAR_EL1 = 6,
    SPR_ACTLR_EL1 = 7,
};

static uint8_t* dram_shm;
static uint8_t* csr_shm;

// Translate a dmem virtual address. EL1 is identity-mapped; EL0 walks the
// flat 200-entry table at TTBR0_EL1.
static bool translate_dmem(VTop* top, uint64_t vaddr, uint64_t* paddr) {
    if (top->el) {
        if (vaddr >= DRAM_SPAN) return false;
        *paddr = vaddr;
        return true;
    }
    uint64_t ttbr   = top->sprf[SPR_TTBR0_EL1];
    uint64_t vpn    = vaddr >> 12;
    uint64_t offset = vaddr & 0xFFFULL;
    uint64_t tte_addr = ttbr + (vpn * 8);
    if (tte_addr + 8 > DRAM_SPAN) return false;
    uint64_t pte;
    std::memcpy(&pte, &dram_shm[tte_addr], 8);
    if (!(pte & 1)) return false;
    *paddr = (pte & ~0xFFFULL) | offset;
    return *paddr + 8 <= DRAM_SPAN;
}

static void mirror_state(VTop* top) {
    for (int i = 0; i < 31; i++) {
        *(volatile uint64_t*)(csr_shm + CSR_X_REGS_BASE + (i * 8)) = top->x_regs[i];
    }
    *(volatile uint64_t*)(csr_shm + CSR_PC)        = top->debug_commit_pc;
    *(volatile uint64_t*)(csr_shm + CSR_SP_EL0)    = top->sprf[SPR_SP_EL0];
    *(volatile uint64_t*)(csr_shm + CSR_SP_EL1)    = top->sprf[SPR_SP_EL1];
    *(volatile uint64_t*)(csr_shm + CSR_ELR_EL1)   = top->sprf[SPR_ELR_EL1];
    *(volatile uint64_t*)(csr_shm + CSR_SPSR_EL1)  = top->sprf[SPR_SPSR_EL1];
    *(volatile uint64_t*)(csr_shm + CSR_ESR_EL1)   = top->sprf[SPR_ESR_EL1];
    *(volatile uint64_t*)(csr_shm + CSR_TTBR0_EL1) = top->sprf[SPR_TTBR0_EL1];
    *(volatile uint64_t*)(csr_shm + CSR_VBAR_EL1)  = top->sprf[SPR_VBAR_EL1];
    *(volatile uint64_t*)(csr_shm + CSR_ACTLR_EL1) = top->done
        ? top->debug_commit_spr_value
        : top->sprf[SPR_ACTLR_EL1];
    *(volatile uint32_t*)(csr_shm + CSR_PSTATE)    = ((uint32_t)top->pstate_flags) << 28;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VTop* top = new VTop;

    shm_unlink("/ozone_dram");
    shm_unlink("/ozone_csr");

    int dram_fd = shm_open("/ozone_dram", O_CREAT | O_RDWR, 0666);
    int csr_fd  = shm_open("/ozone_csr",  O_CREAT | O_RDWR, 0666);
    ftruncate(dram_fd, DRAM_SPAN);
    ftruncate(csr_fd,  CSR_SPAN);
    dram_shm = (uint8_t*)mmap(NULL, DRAM_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, dram_fd, 0);
    csr_shm  = (uint8_t*)mmap(NULL, CSR_SPAN,  PROT_READ | PROT_WRITE, MAP_SHARED, csr_fd, 0);
    std::memset(csr_shm, 0, CSR_SPAN);
    // Hold the proc in reset until the host explicitly releases it.
    *(volatile uint32_t*)(csr_shm + CSR_RESET_REG) = 1;

    std::cout << "[Verilator] Shared memory ready. Waiting for reset..." << std::endl;

    top->reset = 1;
    top->startPC = 0;
    top->imem_resp_valid = 0;
    top->itlb_resp_valid = 0;
    top->dmem_load_ready = 1;
    top->dmem_load_received = 0;
    top->dmem_load_resp_valid = 0;
    top->dmem_load_resp_id = 0;
    top->dmem_load_resp_data = 0;
    top->dmem_store_ready = 1;

    bool prev_reset = true;
    bool done_latched = false;
    bool imem_line_valid = false;
    bool itlb_line_valid = false;
    uint64_t cycles = 0;
    bool tdebug = false;
    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "+TDEBUG") == 0) {
            tdebug = true;
        }
    }

    while (!Verilated::gotFinish()) {
        cycles++;
        // Sample host inputs from CSR.
        uint32_t reset = *(volatile uint32_t*)(csr_shm + CSR_RESET_REG);
        top->reset   = reset;
        top->startPC = *(volatile uint64_t*)(csr_shm + CSR_START_PC);
        if (reset) {
            imem_line_valid = false;
            itlb_line_valid = false;
        }

        if (reset && !prev_reset) {
            std::cout << "[Verilator] Reset asserted by host" << std::endl;
        } else if (!reset && prev_reset) {
            std::cout << "[Verilator] Reset released, startPC=0x"
                      << std::hex << (uint64_t)top->startPC << std::dec << std::endl;
            done_latched = false;
        }
        prev_reset = reset;

        // Posedge.
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        // Serve memory combinationally based on post-edge outputs.
        if (top->imem_req_valid) {
            uint64_t addr = ((uint64_t)top->imem_req_addr) & ~0x3FULL;
            if (addr + 64 <= DRAM_SPAN) {
                std::memcpy(&top->imem_resp_rdata, &dram_shm[addr], 64);
            } else {
                std::memset(&top->imem_resp_rdata, 0, 64);
            }
            imem_line_valid = true;
        }
        top->imem_resp_valid = imem_line_valid ? 1 : 0;

        if (top->itlb_req_valid) {
            uint64_t addr = ((uint64_t)top->itlb_req_addr) & ~0x3FULL;
            if (addr + 64 <= DRAM_SPAN) {
                std::memcpy(&top->itlb_resp_rdata, &dram_shm[addr], 64);
            } else {
                std::memset(&top->itlb_resp_rdata, 0, 64);
            }
            itlb_line_valid = true;
        }
        top->itlb_resp_valid = itlb_line_valid ? 1 : 0;

        // Default load response off; drive it the same cycle a load fires.
        top->dmem_load_received  = 0;
        top->dmem_load_resp_valid = 0;
        if (top->dmem_load_valid && top->dmem_load_ready) {
            uint64_t paddr;
            if (translate_dmem(top, (uint64_t)top->dmem_load_vaddr, &paddr)) {
                uint64_t data;
                std::memcpy(&data, &dram_shm[paddr], 8);
                top->dmem_load_resp_data  = data;
                top->dmem_load_resp_id    = top->dmem_load_id;
                top->dmem_load_resp_valid = 1;
                top->dmem_load_received   = 1;
            } else {
                std::cerr << "[Verilator] dmem load translation failed for vaddr=0x"
                          << std::hex << (uint64_t)top->dmem_load_vaddr << std::dec << std::endl;
            }
        }

        if (top->dmem_store_valid && top->dmem_store_ready) {
            uint64_t paddr;
            if (translate_dmem(top, (uint64_t)top->dmem_store_vaddr, &paddr)) {
                uint64_t value = top->dmem_store_value;
                std::memcpy(&dram_shm[paddr], &value, 8);
            } else {
                std::cerr << "[Verilator] dmem store translation failed for vaddr=0x"
                          << std::hex << (uint64_t)top->dmem_store_vaddr << std::dec << std::endl;
            }
        }

        top->eval();

        if (!done_latched) {
            mirror_state(top);
        }
        if (tdebug && !reset && ((cycles & 0xfffffULL) == 0)) {
            std::cout << "[TDEBUG] cyc=" << cycles
                      << " el=" << (int)top->el
                      << " fe_pc=0x" << std::hex << (uint64_t)top->debug_fe_pc
                      << " fe_v=" << std::dec << (int)top->debug_fe_valid
                      << " fe_r=" << (int)top->debug_fe_ready
                      << " flush=" << (int)top->debug_flush
                      << " redir=0x" << std::hex << (uint64_t)top->debug_redirect_pc
                      << " fetch_pc=0x" << (uint64_t)top->debug_fetch_pc
                      << " itlb_hit=" << std::dec << (int)top->debug_itlb_hit
                      << " itlb_ready=" << (int)top->debug_itlb_ready
                      << " itlb_valid=" << (int)top->debug_itlb_valid
                      << " itlb_pending=" << (int)top->debug_itlb_pending
                      << " imem_req=" << std::dec << (int)top->imem_req_valid
                      << " imem_addr=0x" << std::hex << (uint64_t)top->imem_req_addr
                      << " itlb_req=" << std::dec << (int)top->itlb_req_valid
                      << " itlb_addr=0x" << std::hex << (uint64_t)top->itlb_req_addr
                      << " itlb_pte=0x" << (uint64_t)top->debug_itlb_pte
                      << " x0=0x" << (uint64_t)top->x_regs[0]
                      << " x1=0x" << (uint64_t)top->x_regs[1]
                      << " x3=0x" << (uint64_t)top->x_regs[3]
                      << " actlr=0x" << (uint64_t)top->sprf[SPR_ACTLR_EL1]
                      << std::dec << std::endl;
        }
        if (top->done && !done_latched) {
            done_latched = true;
            std::cout << "[Verilator] done asserted; final state mirrored to CSR" << std::endl;
        }
        *(volatile uint32_t*)(csr_shm + CSR_STATUS_REG) = done_latched ? CSR_DONE_BIT : 0;

        // Yield occasionally so the host can update SHM without throttling every RTL tick.
        if ((cycles & 0x3ffULL) == 0) {
            usleep(1);
        }
    }

    munmap(dram_shm, DRAM_SPAN);
    munmap(csr_shm, CSR_SPAN);
    close(dram_fd);
    close(csr_fd);
    delete top;
    return 0;
}

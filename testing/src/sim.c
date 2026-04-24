#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <capstone/capstone.h>
#include <elf.h>
#include <math.h>
#include "sim.h"
#include "log.h"

// Flags: N (31), Z (30), C (29), V (28)
#define FLAG_N (1U << 31)
#define FLAG_Z (1U << 30)
#define FLAG_C (1U << 29)
#define FLAG_V (1U << 28)

void sim_init(cpu_state_t* cpu, ozone_config_t* config) {
    memset(cpu, 0, sizeof(cpu_state_t));
    cpu->dram = malloc(DRAM_SIZE);
    memset(cpu->dram, 0, DRAM_SIZE);
    cpu->modified_bitmap = calloc(DRAM_SIZE / 8, 1);
    cpu->dram_base = 0; // DRAM starts at physical address 0
    cpu->pc = config->reset_vector;
    cpu->entry = config->reset_vector;
    cpu->el = 1; 
    cpu->ttbr0_el1 = config->ttbr0;
    cpu->actlr_el1 = 0;
    cpu->terminated = false;
    cpu->terminate_val = config->terminate_val;
    cpu->sp_el1 = config->sp_el1;
    cpu->sp_el0 = config->sp_el0;
    
    // Initial return address is 0 to indicate termination on exit
    cpu->x[30] = 0; 
}

void sim_destroy(cpu_state_t* cpu) {
    if (cpu->dram) free(cpu->dram);
    if (cpu->modified_bitmap) free(cpu->modified_bitmap);
}

static void mark_modified(cpu_state_t* cpu, uint64_t addr, size_t size) {
    uint64_t offset = addr - cpu->dram_base;
    for (size_t i = 0; i < size; i++) {
        uint64_t byte_off = offset + i;
        if (byte_off < DRAM_SIZE) {
            cpu->modified_bitmap[byte_off / 8] |= (1 << (byte_off % 8));
        }
    }
}

static void load_elf(cpu_state_t* cpu, const char* binary_path) {
    FILE* f = fopen(binary_path, "rb");
    if (!f) {
        plog(LOG_ERROR, "Couldn't open ELF: %s\n", binary_path);
        exit(-1);
    }
    Elf64_Ehdr ehdr;
    if (fread(&ehdr, 1, sizeof(ehdr), f) != sizeof(ehdr)) {
        plog(LOG_ERROR, "Failed to read ELF header: %s\n", binary_path);
        exit(-1);
    }
    if (memcmp(ehdr.e_ident, ELFMAG, SELFMAG) != 0) {
        plog(LOG_ERROR, "Not an ELF file: %s\n", binary_path);
        exit(-1);
    }
    cpu->entry = ehdr.e_entry;
    cpu->pc = ehdr.e_entry;
    fseek(f, (long)ehdr.e_phoff, SEEK_SET);
    Elf64_Phdr phdr;
    for (int i = 0; i < (int)ehdr.e_phnum; i++) {
        if (fread(&phdr, 1, sizeof(phdr), f) != sizeof(phdr)) {
            plog(LOG_ERROR, "Failed to read program header %d\n", i);
            exit(-1);
        }
        if (phdr.p_type == PT_LOAD) {
            long current_pos = ftell(f);
            fseek(f, (long)phdr.p_offset, SEEK_SET);
            uint64_t dram_offset = phdr.p_paddr - cpu->dram_base;
            if (dram_offset + phdr.p_memsz > DRAM_SIZE) {
                plog(LOG_ERROR, "Segment %d too large for DRAM\n", i);
                exit(-1);
            }
            if (fread(&cpu->dram[dram_offset], 1, phdr.p_filesz, f) != phdr.p_filesz) {
                plog(LOG_ERROR, "Failed to read segment %d\n", i);
                exit(-1);
            }
            if (phdr.p_memsz > phdr.p_filesz) {
                memset(&cpu->dram[dram_offset + phdr.p_filesz], 0, phdr.p_memsz - phdr.p_filesz);
            }
            plog(LOG_INFO, "Loaded ELF segment %d at 0x%"PRIx64" (memsz 0x%"PRIx64")\n", i, phdr.p_paddr, phdr.p_memsz);
            fseek(f, current_pos, SEEK_SET);
        }
    }
    fclose(f);
}

static int reg_to_idx(arm64_reg reg) {
    if (reg >= ARM64_REG_X0 && reg <= ARM64_REG_X28) return reg - ARM64_REG_X0;
    if (reg == ARM64_REG_X29 || reg == ARM64_REG_FP) return 29;
    if (reg == ARM64_REG_X30 || reg == ARM64_REG_LR) return 30;
    if (reg >= ARM64_REG_W0 && reg <= ARM64_REG_W30) return reg - ARM64_REG_W0;
    return -1;
}

static int vreg_to_idx(arm64_reg reg) {
    if (reg >= ARM64_REG_V0 && reg <= ARM64_REG_V31) return reg - ARM64_REG_V0;
    if (reg >= ARM64_REG_D0 && reg <= ARM64_REG_D31) return reg - ARM64_REG_D0;
    if (reg >= ARM64_REG_S0 && reg <= ARM64_REG_S31) return reg - ARM64_REG_S0;
    if (reg >= ARM64_REG_Q0 && reg <= ARM64_REG_Q31) return reg - ARM64_REG_Q0;
    return -1;
}

static uint64_t get_reg(cpu_state_t* cpu, arm64_reg reg) {
    if (reg == ARM64_REG_XZR || reg == ARM64_REG_WZR) return 0;
    if (reg == ARM64_REG_SP || reg == ARM64_REG_WSP) return (cpu->el == 0) ? cpu->sp_el0 : cpu->sp_el1;
    int idx = reg_to_idx(reg);
    if (idx != -1) return cpu->x[idx];
    idx = vreg_to_idx(reg);
    if (idx != -1) return cpu->v[idx];
    return 0;
}

static void set_reg(cpu_state_t* cpu, arm64_reg reg, uint64_t val) {
    if (reg == ARM64_REG_XZR || reg == ARM64_REG_WZR) return;
    if (reg == ARM64_REG_SP || reg == ARM64_REG_WSP) {
        if (cpu->el == 0) cpu->sp_el0 = val; else cpu->sp_el1 = val;
        plog(LOG_DEBUG, "    SP_EL%d = 0x%"PRIx64"\n", cpu->el, val);
        return;
    }
    int idx = reg_to_idx(reg);
    if (idx != -1) {
        cpu->x[idx] = val;
        plog(LOG_DEBUG, "    X%d = 0x%"PRIx64"\n", idx, val);
        return;
    }
    idx = vreg_to_idx(reg);
    if (idx != -1) {
        cpu->v[idx] = val;
        plog(LOG_DEBUG, "    V%d = 0x%"PRIx64"\n", idx, val);
    }
}

static uint64_t apply_shift(uint64_t val, arm64_shifter type, unsigned int amount) {
    switch (type) {
        case ARM64_SFT_LSL: return val << amount;
        case ARM64_SFT_LSR: return val >> amount;
        case ARM64_SFT_ASR: return (uint64_t)(((int64_t)val) >> amount);
        case ARM64_SFT_ROR: return (val >> amount) | (val << (64 - amount));
        default: return val;
    }
}

static void update_flags_add(cpu_state_t* cpu, uint64_t op1, uint64_t op2, uint64_t res) {
    cpu->pstate &= ~(FLAG_N | FLAG_Z | FLAG_C | FLAG_V);
    if (res & (1ULL << 63)) cpu->pstate |= FLAG_N;
    if (res == 0) cpu->pstate |= FLAG_Z;
    if (res < op1) cpu->pstate |= FLAG_C;
    if (((op1 ^ res) & (op2 ^ res)) & (1ULL << 63)) cpu->pstate |= FLAG_V;
}

static void update_flags_sub(cpu_state_t* cpu, uint64_t op1, uint64_t op2, uint64_t res) {
    cpu->pstate &= ~(FLAG_N | FLAG_Z | FLAG_C | FLAG_V);
    if (res & (1ULL << 63)) cpu->pstate |= FLAG_N;
    if (res == 0) cpu->pstate |= FLAG_Z;
    if (op1 >= op2) cpu->pstate |= FLAG_C;
    if (((op1 ^ op2) & (op1 ^ res)) & (1ULL << 63)) cpu->pstate |= FLAG_V;
}

static void update_flags_logic(cpu_state_t* cpu, uint64_t res) {
    cpu->pstate &= ~(FLAG_N | FLAG_Z | FLAG_C | FLAG_V);
    if (res & (1ULL << 63)) cpu->pstate |= FLAG_N;
    if (res == 0) cpu->pstate |= FLAG_Z;
}

static bool check_cond(cpu_state_t* cpu, arm64_cc cc) {
    bool n = (cpu->pstate & FLAG_N) != 0, z = (cpu->pstate & FLAG_Z) != 0, c = (cpu->pstate & FLAG_C) != 0, v = (cpu->pstate & FLAG_V) != 0;
    switch (cc) {
        case ARM64_CC_EQ: return z; case ARM64_CC_NE: return !z;
        case ARM64_CC_HS: return c; case ARM64_CC_LO: return !c;
        case ARM64_CC_MI: return n; case ARM64_CC_PL: return !n;
        case ARM64_CC_VS: return v; case ARM64_CC_VC: return !v;
        case ARM64_CC_HI: return c && !z; case ARM64_CC_LS: return !c || z;
        case ARM64_CC_GE: return n == v; case ARM64_CC_LT: return n != v;
        case ARM64_CC_GT: return !z && (n == v); case ARM64_CC_LE: return z || (n != v);
        default: return true;
    }
}

static bool translate_address(cpu_state_t* cpu, uint64_t va, uint64_t* pa) {
    if (cpu->el != 0) {
        *pa = va;
        return true;
    }
    uint64_t vpn = va >> 12;
    uint64_t offset = va & 0xFFF;
    if (vpn >= 2048) return false;
    uint64_t tte_addr = cpu->ttbr0_el1 + (vpn * 8);
    uint64_t tte = 0;
    if (tte_addr >= DRAM_SIZE) return false;
    memcpy(&tte, &cpu->dram[tte_addr], 8);
    if (!(tte & 1)) return false;
    *pa = (tte & ~0xFFFULL) | offset;
    return true;
}

static void trigger_exception(cpu_state_t* cpu, uint64_t next_pc_on_eret) {
    cpu->elr_el1 = next_pc_on_eret;
    cpu->spsr_el1 = cpu->el;
    cpu->el = 1;
    cpu->pc = cpu->vbar_el1 + 0x400; 
}

void sim_run(cpu_state_t* cpu, const char* binary_path) {
    load_elf(cpu, binary_path);
    csh handle;
    if (cs_open(CS_ARCH_ARM64, CS_MODE_ARM, &handle) != CS_ERR_OK) return;
    cs_option(handle, CS_OPT_DETAIL, CS_OPT_ON);
    cs_insn *insn;
    size_t count;
    while (!cpu->terminated) {
        uint64_t pa_pc;
        if (!translate_address(cpu, cpu->pc, &pa_pc)) {
            plog(LOG_INFO, "Instruction Fetch Fault at 0x%"PRIx64". Trap to EL1.\n", cpu->pc);
            trigger_exception(cpu, cpu->pc);
            continue;
        }
        uint64_t dram_offset = pa_pc - cpu->dram_base;
        if (dram_offset >= DRAM_SIZE) break;
        uint32_t raw_insn = *(uint32_t*)(&cpu->dram[dram_offset]);
        count = cs_disasm(handle, (uint8_t*)&raw_insn, 4, cpu->pc, 1, &insn);
        if (count > 0) {
            plog(LOG_DEBUG, "0x%"PRIx64": %s %s\n", insn[0].address, insn[0].mnemonic, insn[0].op_str);
            cs_detail *detail = insn[0].detail;
            cs_arm64 *arm64 = &detail->arm64;
            uint64_t next_pc = cpu->pc + 4;
            bool fault = false;
            switch (insn[0].id) {
                case ARM64_INS_ADD: case ARM64_INS_ADDS: case ARM64_INS_CMN: {
                    uint64_t op1 = get_reg(cpu, arm64->operands[0].reg);
                    uint64_t op2;
                    if (insn[0].id == ARM64_INS_CMN) {
                        op2 = (arm64->operands[1].type == ARM64_OP_IMM) ? arm64->operands[1].imm : apply_shift(get_reg(cpu, arm64->operands[1].reg), arm64->operands[1].shift.type, arm64->operands[1].shift.value);
                    } else {
                        op1 = get_reg(cpu, arm64->operands[1].reg);
                        op2 = (arm64->operands[2].type == ARM64_OP_IMM) ? arm64->operands[2].imm : apply_shift(get_reg(cpu, arm64->operands[2].reg), arm64->operands[2].shift.type, arm64->operands[2].shift.value);
                    }
                    if (arm64->operands[2].type == ARM64_OP_IMM && arm64->operands[2].shift.type != ARM64_SFT_INVALID) {
                        op2 = apply_shift(op2, arm64->operands[2].shift.type, arm64->operands[2].shift.value);
                    }
                    uint64_t res = op1 + op2;
                    if (insn[0].id != ARM64_INS_CMN) set_reg(cpu, arm64->operands[0].reg, res);
                    if (insn[0].id == ARM64_INS_ADDS || insn[0].id == ARM64_INS_CMN) update_flags_add(cpu, op1, op2, res);
                    break;
                }
                case ARM64_INS_SUB: case ARM64_INS_SUBS: case ARM64_INS_CMP: {
                    uint64_t op1 = get_reg(cpu, arm64->operands[0].reg);
                    uint64_t op2;
                    if (insn[0].id == ARM64_INS_CMP) {
                        op2 = (arm64->operands[1].type == ARM64_OP_IMM) ? arm64->operands[1].imm : apply_shift(get_reg(cpu, arm64->operands[1].reg), arm64->operands[1].shift.type, arm64->operands[1].shift.value);
                    } else {
                        op1 = get_reg(cpu, arm64->operands[1].reg);
                        op2 = (arm64->operands[2].type == ARM64_OP_IMM) ? arm64->operands[2].imm : apply_shift(get_reg(cpu, arm64->operands[2].reg), arm64->operands[2].shift.type, arm64->operands[2].shift.value);
                    }
                    uint64_t res = op1 - op2;
                    if (insn[0].id != ARM64_INS_CMP) set_reg(cpu, arm64->operands[0].reg, res);
                    if (insn[0].id == ARM64_INS_SUBS || insn[0].id == ARM64_INS_CMP) update_flags_sub(cpu, op1, op2, res);
                    break;
                }
                case ARM64_INS_MOVZ: case ARM64_INS_MOVK: {
                    uint64_t val = (insn[0].id == ARM64_INS_MOVZ) ? 0 : get_reg(cpu, arm64->operands[0].reg);
                    int shift = arm64->operands[1].shift.value;
                    if (insn[0].id == ARM64_INS_MOVZ) val = arm64->operands[1].imm << shift;
                    else val = (val & ~(0xFFFFULL << shift)) | (arm64->operands[1].imm << shift);
                    set_reg(cpu, arm64->operands[0].reg, val); break;
                }
                case ARM64_INS_ADRP: set_reg(cpu, arm64->operands[0].reg, arm64->operands[1].imm); break;
                case ARM64_INS_EOR: case ARM64_INS_ORR: case ARM64_INS_ANDS: case ARM64_INS_AND: case ARM64_INS_ORN: case ARM64_INS_MOV: case ARM64_INS_TST: {
                    uint64_t op1, op2;
                    if (insn[0].id == ARM64_INS_MOV) {
                        op1 = 0; op2 = (arm64->operands[1].type == ARM64_OP_IMM) ? arm64->operands[1].imm : get_reg(cpu, arm64->operands[1].reg);
                    } else if (insn[0].id == ARM64_INS_TST) {
                        op1 = get_reg(cpu, arm64->operands[0].reg);
                        op2 = (arm64->operands[1].type == ARM64_OP_IMM) ? arm64->operands[1].imm : apply_shift(get_reg(cpu, arm64->operands[1].reg), arm64->operands[1].shift.type, arm64->operands[1].shift.value);
                    } else if (arm64->op_count == 3) {
                        op1 = get_reg(cpu, arm64->operands[1].reg);
                        op2 = (arm64->operands[2].type == ARM64_OP_IMM) ? arm64->operands[2].imm : apply_shift(get_reg(cpu, arm64->operands[2].reg), arm64->operands[2].shift.type, arm64->operands[2].shift.value);
                    } else {
                        op1 = 0; op2 = (arm64->operands[1].type == ARM64_OP_IMM) ? arm64->operands[1].imm : get_reg(cpu, arm64->operands[1].reg);
                    }
                    if (insn[0].id == ARM64_INS_ORN) op2 = ~op2;
                    uint64_t res = (insn[0].id == ARM64_INS_EOR) ? (op1 ^ op2) : ((insn[0].id == ARM64_INS_ORR || insn[0].id == ARM64_INS_ORN || insn[0].id == ARM64_INS_MOV) ? (op1 | op2) : (op1 & op2));
                    if (insn[0].id != ARM64_INS_TST) set_reg(cpu, arm64->operands[0].reg, res);
                    if (insn[0].id == ARM64_INS_ANDS || insn[0].id == ARM64_INS_TST) update_flags_logic(cpu, res);
                    break;
                }
                case ARM64_INS_UBFM: case ARM64_INS_SBFM: case ARM64_INS_LSL: case ARM64_INS_LSR: case ARM64_INS_ASR: {
                    uint64_t src = get_reg(cpu, arm64->operands[1].reg), res = 0;
                    if (insn[0].id == ARM64_INS_LSL) res = src << arm64->operands[2].imm;
                    else if (insn[0].id == ARM64_INS_LSR) res = src >> arm64->operands[2].imm;
                    else if (insn[0].id == ARM64_INS_ASR) res = (uint64_t)((int64_t)src >> arm64->operands[2].imm);
                    else {
                        uint64_t r = arm64->operands[2].imm, s = arm64->operands[3].imm;
                        if (s >= r) res = (src >> r) & ((1ULL << (s - r + 1)) - 1);
                        else res = (src & ((1ULL << (s + 1)) - 1)) << (64 - r);
                        if (insn[0].id == ARM64_INS_SBFM) {
                            if (src & (1ULL << s)) res |= ~((1ULL << (s + 1)) - 1);
                        }
                    }
                    set_reg(cpu, arm64->operands[0].reg, res); break;
                }
                case ARM64_INS_LSLV: case ARM64_INS_LSRV: case ARM64_INS_ASRV: {
                    uint64_t op1 = get_reg(cpu, arm64->operands[1].reg), op2 = get_reg(cpu, arm64->operands[2].reg) & 63;
                    set_reg(cpu, arm64->operands[0].reg, (insn[0].id == ARM64_INS_LSLV) ? (op1 << op2) : ((insn[0].id == ARM64_INS_LSRV) ? (op1 >> op2) : (uint64_t)((int64_t)op1 >> op2)));
                    break;
                }
                case ARM64_INS_STUR: {
                    uint64_t va = get_reg(cpu, arm64->operands[1].mem.base) + arm64->operands[1].mem.disp, pa;
                    if (!translate_address(cpu, va, &pa)) {
                        plog(LOG_INFO, "Store Page Fault at 0x%"PRIx64". Trap to EL1.\n", va);
                        trigger_exception(cpu, cpu->pc); fault = true;
                    } else {
                        uint64_t val = get_reg(cpu, arm64->operands[0].reg);
                        if (pa < DRAM_SIZE) { memcpy(&cpu->dram[pa], &val, 8); mark_modified(cpu, pa, 8); }
                    }
                    break;
                }
                case ARM64_INS_LDUR: {
                    uint64_t va = get_reg(cpu, arm64->operands[1].mem.base) + arm64->operands[1].mem.disp, pa, val = 0;
                    if (!translate_address(cpu, va, &pa)) {
                        plog(LOG_INFO, "Load Page Fault at 0x%"PRIx64". Trap to EL1.\n", va);
                        trigger_exception(cpu, cpu->pc); fault = true;
                    } else {
                        if (pa < DRAM_SIZE) { memcpy(&val, &cpu->dram[pa], 8); plog(LOG_DEBUG, "    LDUR [0x%"PRIx64"] -> 0x%"PRIx64"\n", pa, val); }
                        set_reg(cpu, arm64->operands[0].reg, val);
                    }
                    break;
                }
                case ARM64_INS_FADD: case ARM64_INS_FSUB: case ARM64_INS_FMUL: {
                    double d1, d2, dr; uint64_t u1 = get_reg(cpu, arm64->operands[1].reg), u2 = get_reg(cpu, arm64->operands[2].reg);
                    memcpy(&d1, &u1, 8); memcpy(&d2, &u2, 8);
                    dr = (insn[0].id == ARM64_INS_FADD) ? d1 + d2 : ((insn[0].id == ARM64_INS_FSUB) ? d1 - d2 : d1 * d2);
                    memcpy(&u1, &dr, 8); set_reg(cpu, arm64->operands[0].reg, u1); break;
                }
                case ARM64_INS_FNEG: case ARM64_INS_FMOV: {
                    uint64_t u = get_reg(cpu, arm64->operands[1].reg);
                    if (insn[0].id == ARM64_INS_FNEG) u ^= (1ULL << 63);
                    set_reg(cpu, arm64->operands[0].reg, u); break;
                }
                case ARM64_INS_FCMP: {
                    double d1, d2; uint64_t u1 = get_reg(cpu, arm64->operands[0].reg), u2 = get_reg(cpu, arm64->operands[1].reg);
                    memcpy(&d1, &u1, 8); memcpy(&d2, &u2, 8);
                    cpu->pstate &= ~(FLAG_N | FLAG_Z | FLAG_C | FLAG_V);
                    if (isnan(d1) || isnan(d2)) cpu->pstate |= (FLAG_C | FLAG_V | FLAG_Z);
                    else if (d1 == d2) cpu->pstate |= (FLAG_Z | FLAG_C);
                    else if (d1 < d2) cpu->pstate |= FLAG_N;
                    else cpu->pstate |= FLAG_C;
                    break;
                }
                case ARM64_INS_B: if (arm64->cc == ARM64_CC_INVALID || check_cond(cpu, arm64->cc)) next_pc = (uint64_t)arm64->operands[0].imm; break;
                case ARM64_INS_BL: set_reg(cpu, ARM64_REG_X30, next_pc); next_pc = (uint64_t)arm64->operands[0].imm; break;
                case ARM64_INS_RET: {
                    next_pc = get_reg(cpu, arm64->operands[0].reg ? arm64->operands[0].reg : ARM64_REG_X30);
                    if (next_pc == 0) {
                        if (cpu->el == 0) { plog(LOG_INFO, "EL0 Exception: RET to 0. Jumping to EL1 handler.\n"); trigger_exception(cpu, cpu->pc); fault = true; }
                        else cpu->terminated = true;
                    }
                    break;
                }
                case ARM64_INS_SVC: plog(LOG_INFO, "SVC Exception: Jumping to EL1 handler.\n"); trigger_exception(cpu, next_pc); fault = true; break;
                case ARM64_INS_ERET: next_pc = cpu->elr_el1; cpu->el = cpu->spsr_el1 & 0xF; plog(LOG_INFO, "ERET: Returning to EL%d at 0x%"PRIx64"\n", cpu->el, next_pc); break;
                case ARM64_INS_MSR: case ARM64_INS_MRS: {
                    arm64_sysreg sys = (arm64_sysreg)((insn[0].id == ARM64_INS_MSR) ? arm64->operands[0].reg : arm64->operands[1].reg);
                    if (insn[0].id == ARM64_INS_MSR) {
                        uint64_t val = get_reg(cpu, arm64->operands[1].reg);
                        if (sys == ARM64_SYSREG_SP_EL0) cpu->sp_el0 = val;
                        else if (sys == ARM64_SYSREG_SPSR_EL1) cpu->spsr_el1 = val;
                        else if (sys == ARM64_SYSREG_ELR_EL1) cpu->elr_el1 = val;
                        else if (sys == ARM64_SYSREG_VBAR_EL1) cpu->vbar_el1 = val;
                        else if (sys == ARM64_SYSREG_ACTLR_EL1) {
                            cpu->actlr_el1 = val;
                            if (val == cpu->terminate_val) {
                                plog(LOG_INFO, "ACTLR_EL1 written with terminate value 0x%"PRIx64". Terminating.\n", val);
                                cpu->terminated = true;
                            }
                        }
                    } else {
                        uint64_t val = 0;
                        if (sys == ARM64_SYSREG_SP_EL0) val = cpu->sp_el0;
                        else if (sys == ARM64_SYSREG_SPSR_EL1) val = cpu->spsr_el1;
                        else if (sys == ARM64_SYSREG_ELR_EL1) val = cpu->elr_el1;
                        else if (sys == ARM64_SYSREG_VBAR_EL1) val = cpu->vbar_el1;
                        else if (sys == ARM64_SYSREG_ACTLR_EL1) val = cpu->actlr_el1;
                        set_reg(cpu, arm64->operands[0].reg, val);
                    }
                    break;
                }
                case ARM64_INS_MVN: { uint64_t val = (arm64->operands[1].type == ARM64_OP_IMM) ? arm64->operands[1].imm : get_reg(cpu, arm64->operands[1].reg); set_reg(cpu, arm64->operands[0].reg, ~val); break; }
                case ARM64_INS_NOP: break;
                default: plog(LOG_ERROR, "Unsupported: %s\n", insn[0].mnemonic); cpu->terminated = true; break;
            }
            if (!fault) cpu->pc = next_pc; cs_free(insn, count);
        } else { plog(LOG_ERROR, "Disasm failed at 0x%"PRIx64"\n", cpu->pc); break; }
    }
    cs_close(&handle);
}

void sim_print_state(cpu_state_t* cpu) {
    plog(LOG_INFO, "\n========== Final Architectural State ==========\n");
    plog(LOG_INFO, "PC:     0x%016lx\n", cpu->pc);
    plog(LOG_INFO, "PSTATE: 0x%08x (N:%d Z:%d C:%d V:%d)\n", cpu->pstate, (cpu->pstate & FLAG_N) != 0, (cpu->pstate & FLAG_Z) != 0, (cpu->pstate & FLAG_C) != 0, (cpu->pstate & FLAG_V) != 0);
    plog(LOG_INFO, "EL:     %d\n", cpu->el);
    plog(LOG_INFO, "\nGeneral Purpose Registers:\n");
    for (int i = 0; i < 31; i++) plog(LOG_INFO, "X%-2d: 0x%016lx%s", i, cpu->x[i], (i % 2 == 1) ? "\n" : "    ");
    plog(LOG_INFO, "\n\nSystem Registers:\n");
    plog(LOG_INFO, "SP_EL0:    0x%016lx    SP_EL1:    0x%016lx\n", cpu->sp_el0, cpu->sp_el1);
    plog(LOG_INFO, "SPSR_EL1:  0x%016lx    ELR_EL1:   0x%016lx\n", cpu->spsr_el1, cpu->elr_el1);
    plog(LOG_INFO, "ESR_EL1:   0x%016lx    TTBR0_EL1: 0x%016lx\n", cpu->esr_el1, cpu->ttbr0_el1);
    plog(LOG_INFO, "VBAR_EL1:  0x%016lx    ACTLR_EL1: 0x%016lx\n", cpu->vbar_el1, cpu->actlr_el1);
    plog(LOG_INFO, "\nFloating Point Registers (64-bit):\n");
    for (int i = 0; i < 32; i++) plog(LOG_INFO, "V%-2d: 0x%016lx%s", i, cpu->v[i], (i % 3 == 2) ? "\n" : "    ");
    plog(LOG_INFO, "\n\nModified Memory:\n");
    bool any_mod = false;
    for (uint64_t i = 0; i < DRAM_SIZE; i += 8) {
        bool word_mod = false;
        for (int j = 0; j < 8; j++) if (cpu->modified_bitmap[(i + j) / 8] & (1 << ((i + j) % 8))) { word_mod = true; break; }
        if (word_mod) { uint64_t val; memcpy(&val, &cpu->dram[i], 8); plog(LOG_INFO, "0x%016lx: 0x%016lx\n", cpu->dram_base + i, val); any_mod = true; }
    }
    if (!any_mod) plog(LOG_INFO, "(none)\n");
    plog(LOG_INFO, "================================================\n");
}

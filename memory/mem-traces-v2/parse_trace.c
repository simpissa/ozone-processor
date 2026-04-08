#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef enum {
    OP_MEM_LOAD = 0,
    OP_MEM_STORE = 1,
    OP_MEM_RESOLVE = 2,
    OP_TLB_FILL = 4
} op_e;

const char* get_op_str(uint8_t op) {
    switch (op) {
        case OP_MEM_LOAD:    return "LOAD";
        case OP_MEM_STORE:   return "STORE";
        case OP_MEM_RESOLVE: return "RESOLVE";
        case OP_TLB_FILL:    return "TLB_FILL";
        default:             return "UNKNOWN";
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <trace_file> [limit]\n", argv[0]);
        return 1;
    }

    FILE* f = fopen(argv[1], "rb");
    if (!f) {
        perror("Error opening file");
        return 1;
    }

    int limit = -1;
    if (argc > 2) {
        limit = atoi(argv[2]);
    }

    printf("%7s | %6s | %-10s | %-2s | %-14s | %-2s | %-18s | %-3s | %-10s\n",
           "Trace #", "Acc #", "Op", "ID", "VAddr", "VV", "Value", "VvV", "TLB PAddr");
    printf("------------------------------------------------------------------------------------------------------------------\n");

    uint8_t buffer[16];
    int trace_num = 0;
    int access_num = 0;
    int count = 0;
    while (fread(buffer, 16, 1, f) == 1) {
        uint64_t vaddr = 0;
        for (int i = 0; i < 6; i++) {
            vaddr |= ((uint64_t)buffer[i] << (i * 8));
        }

        uint8_t byte6 = buffer[6];
        uint8_t id = byte6 & 0x0F;
        uint8_t op = (byte6 >> 4) & 0x07;
        uint8_t vaddr_valid = (byte6 >> 7) & 0x01;

        uint64_t value = 0;
        for (int i = 0; i < 8; i++) {
            value |= ((uint64_t)buffer[7+i] << (i * 8));
        }

        uint8_t value_valid = buffer[15] & 0x01;
        uint32_t tlb_paddr = value & 0x3FFFFFFF;

        char access_str[10] = "";
        if (op == OP_MEM_LOAD || op == OP_MEM_STORE) {
            sprintf(access_str, "%d", access_num++);
        }

        if (op == OP_TLB_FILL) {
            printf("%7d | %6s | %-10s | %-2s | 0x%012lx | %-2u | %-18s | %-3u | 0x%08x\n",
                   trace_num++, "", get_op_str(op), "x", vaddr, vaddr_valid, "0x0", value_valid, tlb_paddr);
        } else {
            printf("%7d | %6s | %-10s | %-2u | 0x%012lx | %-2u | 0x%016lx | %-3u | %-10s\n",
                   trace_num++, access_str, get_op_str(op), id, vaddr, vaddr_valid, value, value_valid, "");
        }

        count++;
        if (limit > 0 && count >= limit) break;
    }

    fclose(f);
    return 0;
}

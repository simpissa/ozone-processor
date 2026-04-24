#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define TRACE_RECORD_SIZE 16
#define LSQ_QUEUE_SIZE    16
#define MEM_HASH_SIZE     4096
#define MAX_TRACE_IDS     16

typedef enum {
    OP_MEM_LOAD    = 0,
    OP_MEM_STORE   = 1,
    OP_MEM_RESOLVE = 2,
    OP_TLB_FILL    = 4
} op_e;

typedef struct {
    uint8_t  op;
    uint64_t vaddr;
    uint8_t  vaddr_valid;
    uint64_t value;
    uint8_t  value_valid;
    int      access_num;
    uint8_t  id;
} QueueEntry;

typedef struct MemEntry {
    uint64_t         addr;
    uint64_t         value;
    int              last_access_num;
    struct MemEntry *next;
} MemEntry;

static QueueEntry lsq[LSQ_QUEUE_SIZE];
static int q_head = 0;
static int q_tail = 0;

static MemEntry *memory_hashtable[MEM_HASH_SIZE];
static int total_modified_entries = 0;

uint32_t addr_hash(uint64_t addr) {
    return (uint32_t)(addr % MEM_HASH_SIZE);
}

void update_architectural_memory(uint64_t addr, uint64_t value, int access_num) {
    uint32_t h = addr_hash(addr);
    MemEntry *e = memory_hashtable[h];
    while (e) {
        if (e->addr == addr) {
            e->value = value;
            e->last_access_num = access_num;
            return;
        }
        e = e->next;
    }
    e = (MemEntry*)malloc(sizeof(MemEntry));
    e->addr = addr;
    e->value = value;
    e->last_access_num = access_num;
    e->next = memory_hashtable[h];
    memory_hashtable[h] = e;
    total_modified_entries++;
}

int compare_mem_addr(const void *a, const void *b) {
    MemEntry *ea = *(MemEntry **)a;
    MemEntry *eb = *(MemEntry **)b;
    if (ea->addr < eb->addr) return -1;
    if (ea->addr > eb->addr) return 1;
    return 0;
}

void commit_ready_ops() {
    while (q_head != q_tail) {
        if (lsq[q_head].vaddr_valid && lsq[q_head].value_valid) {
            if (lsq[q_head].op == OP_MEM_STORE) {
                update_architectural_memory(lsq[q_head].vaddr, lsq[q_head].value, lsq[q_head].access_num);
            }
            q_head = (q_head + 1) % LSQ_QUEUE_SIZE;
        } else {
            break; // Head not ready, cannot retire further
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <trace_file> [timestep_limit]\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("fopen"); return 1; }

    int limit = -1;
    if (argc > 2) limit = atoi(argv[2]);

    uint8_t buffer[TRACE_RECORD_SIZE];
    int timestep = 0;
    int total_access_counter = 0;

    while (fread(buffer, TRACE_RECORD_SIZE, 1, f) == 1) {
        timestep++;
        if (limit > 0 && timestep > limit) break;

        // Decode bit-packed trace line (Little Endian)
        uint64_t vaddr = 0;
        for (int i = 0; i < 6; i++) vaddr |= ((uint64_t)buffer[i] << (i * 8));

        uint8_t byte6 = buffer[6];
        uint8_t id    = byte6 & 0x0F;
        uint8_t op    = (byte6 >> 4) & 0x07;
        uint8_t v_val = (byte6 >> 7) & 0x01;

        uint64_t value = 0;
        for (int i = 0; i < 8; i++) value |= ((uint64_t)buffer[7+i] << (i * 8));
        uint8_t  val_val = buffer[15] & 0x01;

        if (op == OP_MEM_LOAD || op == OP_MEM_STORE) {
            int current_access = total_access_counter++;
            lsq[q_tail].op          = op;
            lsq[q_tail].vaddr       = vaddr;
            lsq[q_tail].vaddr_valid = v_val;
            lsq[q_tail].value       = value;
            lsq[q_tail].value_valid = val_val;
            lsq[q_tail].access_num  = current_access;
            lsq[q_tail].id          = id;
            q_tail = (q_tail + 1) % LSQ_QUEUE_SIZE;
        } else if (op == OP_MEM_RESOLVE) {
            // Find oldest incomplete op in LSQ with matching ID
            int idx = q_head;
            while (idx != q_tail) {
                if (lsq[idx].id == id && !(lsq[idx].vaddr_valid && lsq[idx].value_valid)) {
                    if (v_val) {
                        lsq[idx].vaddr       = vaddr;
                        lsq[idx].vaddr_valid = 1;
                    }
                    if (val_val) {
                        lsq[idx].value       = value;
                        lsq[idx].value_valid = 1;
                    }
                    break;
                }
                idx = (idx + 1) % LSQ_QUEUE_SIZE;
            }
        }

        commit_ready_ops();
    }

    // Final Output
    if (total_modified_entries > 0) {
        MemEntry **sorted_list = malloc(sizeof(MemEntry *) * total_modified_entries);
        int list_idx = 0;
        for (int i = 0; i < MEM_HASH_SIZE; i++) {
            MemEntry *e = memory_hashtable[i];
            while (e) {
                sorted_list[list_idx++] = e;
                e = e->next;
            }
        }

        qsort(sorted_list, total_modified_entries, sizeof(MemEntry *), compare_mem_addr);

        printf("Modified architectural memory state (assuming everything commited):\n");
        printf("%-14s | %-18s | %-10s\n", "Address", "Value", "Last Acc #");
        printf("------------------------------------------------------------\n");

        for (int i = 0; i < total_modified_entries; i++) {
            printf("0x%012lx | 0x%016lx | %-10d\n", sorted_list[i]->addr, sorted_list[i]->value, sorted_list[i]->last_access_num);
        }
        free(sorted_list);
    } else {
        printf("No memory modifications recorded.\n");
    }

    fclose(f);
    return 0;
}

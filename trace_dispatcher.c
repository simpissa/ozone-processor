#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

typedef unsigned __int128 u128;

static const char *TRACE_FILE = "mem-traces-v2/mem-traces-v2/traces/dgemm3_lsq88_real.bin";
static const char *COMMIT_LOG = "trace_commits.log";

#define BRIDGE_BASE 0xC0000000
#define BRIDGE_SPAN 0x1000

#define TRACE_DATA_OFFSET   0 
#define CTRL_STATUS_OFFSET  16 // handshake: when reading, bit0=trace_ready, bit1=commit_valid; when writing bit0=trace_submit, bit1=commit_pop
#define COMMIT_DATA_OFFSET  32 // [47:0] is v_addr, [111:48] is commit_value

#define CTRL_TRACE_SUBMIT   0b01
#define CTRL_COMMIT_POP     0b10

#define STATUS_TRACE_READY  0b01
#define STATUS_COMMIT_VALID 0b10

#define TIMEOUT_NS 100000000ULL

static void pulse_control(volatile uint64_t *ctrl_reg, uint64_t mask)
{
    *ctrl_reg = mask;
    *ctrl_reg = 0;
}

static uint64_t curr_time(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((uint64_t)ts.tv_sec * 1000000000ULL) + (uint64_t)ts.tv_nsec;
}

static int read_trace(FILE *trace_fp, u128 *trace)
{
    size_t bytes_read = fread(trace, 1, sizeof(*trace), trace_fp); // little endian

    if (bytes_read == 0) {
        if (feof(trace_fp)) {
            return 0;
        }
        fprintf(stderr, "trace read failed\n");
        return -1;
    }
    if (bytes_read != sizeof(*trace)) {
        fprintf(stderr, "expected 16 bytes trace, got %zu\n", bytes_read);
        return -1;
    }
    return 1;
}

int main(void)
{
    FILE *trace_fp = NULL;
    FILE *commit_fp = NULL;
    int devmem_fd = -1;
    uint8_t *bridge_map = NULL;
    volatile u128 *trace_data_reg;
    volatile uint64_t *ctrl_status_reg;
    volatile u128 *commit_data_reg;
    uint64_t last_progress_ns;
    bool trace_done = false;

    trace_fp = fopen(TRACE_FILE, "rb");
    if (!trace_fp) {
        fprintf(stderr, "fopen(%s) failed: %s\n", TRACE_FILE, strerror(errno));
        return 1;
    }

    commit_fp = fopen(COMMIT_LOG, "w");
    if (!commit_fp) {
        fprintf(stderr, "fopen(%s) failed: %s\n", COMMIT_LOG, strerror(errno));
        fclose(trace_fp);
        return 1;
    }

    devmem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (devmem_fd < 0) {
        fprintf(stderr, "open(/dev/mem) failed: %s\n", strerror(errno));
        fclose(trace_fp);
        fclose(commit_fp);
        return 1;
    }

    bridge_map = (uint8_t *)mmap(NULL,
                                 BRIDGE_SPAN,
                                 PROT_READ | PROT_WRITE,
                                 MAP_SHARED,
                                 devmem_fd,
                                 BRIDGE_BASE);
    if (bridge_map == MAP_FAILED) {
        fprintf(stderr, "mmap bridge failed: %s\n", strerror(errno));
        close(devmem_fd);
        fclose(trace_fp);
        fclose(commit_fp);
        return 1;
    }

    trace_data_reg = (volatile u128 *)(bridge_map + TRACE_DATA_OFFSET);
    ctrl_status_reg = (volatile uint64_t *)(bridge_map + CTRL_STATUS_OFFSET);
    commit_data_reg = (volatile u128 *)(bridge_map + COMMIT_DATA_OFFSET);
    last_progress_ns = now_ns();

    while (true) {
        uint64_t status = *ctrl_status_reg;
        bool did_work = false;

        if ((status & STATUS_COMMIT_VALID) != 0u) {
            u128 commit_word = *commit_data_reg;
            uint64_t commit_vaddr = (uint64_t)(commit_word & ((((u128)1) << 48) - 1));
            uint64_t commit_value = (uint64_t)(commit_word >> 48);

            // log commit_vaddr + commit_value
            fprintf(commit_fp, "0x%012" PRIx64 " 0x%016" PRIx64 "\n", commit_vaddr, commit_value);
            pulse_control(ctrl_status_reg, CTRL_COMMIT_POP);
            last_progress_ns = now_ns();
            did_work = true;
        }

        if (!trace_done && (status & STATUS_TRACE_READY) != 0u) {
            u128 trace;
            int rc = read_trace(trace_fp, &trace);

            if (rc < 0) {
                munmap(bridge_map, BRIDGE_SPAN);
                close(devmem_fd);
                fclose(trace_fp);
                fclose(commit_fp);
                return 1;
            }

            if (rc == 0) {
                trace_done = true;
            } else {
                *trace_data_reg = trace;
                pulse_control(ctrl_status_reg, CTRL_TRACE_SUBMIT);
                last_progress_ns = now_ns();
                did_work = true;
            }
        }

        // keep waiting TIMEOUT_NS for any remaining store commits
        if (trace_done && (curr_time() - last_progress_ns >= TIMEOUT_NS)) {
            break;
        }

        if (!did_work) {
            usleep(1);
        }
    }

    munmap(bridge_map, BRIDGE_SPAN);
    close(devmem_fd);
    fclose(trace_fp);
    fclose(commit_fp);
    return 0;
}

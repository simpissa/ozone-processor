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
// log of all store commits; we can also log loads but they're not needed for architectural state
static const char *COMMIT_LOG = "trace_commits.log";

#define BRIDGE_BASE 0xC0000000
#define BRIDGE_SPAN 0x1000

#define TRACE_DATA_OFFSET             0
#define HPS_TO_FPGA_HANDSHAKE_OFFSET 16
#define COMMIT_DATA_OFFSET           32 // [47:0] is v_addr, [111:48] is commit_value
#define FPGA_TO_HPS_HANDSHAKE_OFFSET 48

#define TRACE_VALID  0b01
#define COMMIT_POP   0b10

#define TRACE_READY  0b01
#define COMMIT_VALID 0b10

#define TIMEOUT_NS 100000000ULL

static void pulse_command(volatile uint64_t *cmd_reg, uint64_t mask)
{
    *cmd_reg = mask;
    *cmd_reg = 0;
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
    volatile uint64_t *hps_to_fpga_handshake_reg;
    volatile u128 *commit_data_reg;
    volatile uint64_t *fpga_to_hps_handshake_reg;
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
    hps_to_fpga_handshake_reg = (volatile uint64_t *)(bridge_map + HPS_TO_FPGA_HANDSHAKE_OFFSET);
    commit_data_reg = (volatile u128 *)(bridge_map + COMMIT_DATA_OFFSET);
    fpga_to_hps_handshake_reg = (volatile uint64_t *)(bridge_map + FPGA_TO_HPS_HANDSHAKE_OFFSET);
    last_progress_ns = curr_time();

    while (true) {
        uint64_t status = *fpga_to_hps_handshake_reg;
        bool did_work = false;

        if ((status & COMMIT_VALID) != 0u) {
            u128 commit_word = *commit_data_reg;
            uint64_t commit_vaddr = (uint64_t)(commit_word & ((((u128)1) << 48) - 1));
            uint64_t commit_value = (uint64_t)(commit_word >> 48);

            // log commit_vaddr + commit_value
            fprintf(commit_fp, "0x%012" PRIx64 " 0x%016" PRIx64 "\n", commit_vaddr, commit_value);
            pulse_command(hps_to_fpga_handshake_reg, COMMIT_POP);
            last_progress_ns = curr_time();
            did_work = true;
        }

        if (!trace_done && (status & TRACE_READY) != 0u) {
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
                pulse_command(hps_to_fpga_handshake_reg, TRACE_VALID);
                last_progress_ns = curr_time();
                did_work = true;
            }
        }

        // keep waiting TIMEOUT_NS for any remaining store commits
        if (trace_done && (curr_time() - last_progress_ns >= TIMEOUT_NS)) {
            break;
        }

        if (!did_work) {
            struct timespec sleep_time = {0, 1000};
            nanosleep(&sleep_time, NULL);
        }
    }

    munmap(bridge_map, BRIDGE_SPAN);
    close(devmem_fd);
    fclose(trace_fp);
    fclose(commit_fp);
    return 0;
}

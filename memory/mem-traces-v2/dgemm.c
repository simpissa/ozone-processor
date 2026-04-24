#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/*
 * Deterministic DGEMM with 6 loops and packing (Goto-style approach).
 */

#define MC 64
#define KC 64
#define NC 64

#define MR 4
#define NR 4

#define MAX_DIM 16

// Static buffers to avoid malloc non-determinism
double static_A[MAX_DIM * MAX_DIM];
double static_B[MAX_DIM * MAX_DIM];

// Global packing buffers
double packA[MC * KC];
double packB[KC * NC];

void pack_A_block(int m, int k, double *A, int lda, double *buffer) {
    for (int j = 0; j < k; j++) {
        for (int i = 0; i < m; i++) {
            *buffer++ = A[i + j * lda];
        }
    }
}

void pack_B_block(int k, int n, double *B, int ldb, double *buffer) {
    for (int i = 0; i < k; i++) {
        for (int j = 0; j < n; j++) {
            *buffer++ = B[j + i * ldb];
        }
    }
}

void dgemm_micro_kernel(int k, double *A, double *B, double *C, int ldc) {
    for (int j = 0; j < NR; j++) {
        for (int i = 0; i < MR; i++) {
            for (int l = 0; l < k; l++) {
                C[i + j * ldc] += A[i + l * MR] * B[j + l * NR];
            }
        }
    }
}

void dgemm_goto(int M, int N, int K, double *A, double *B, double *C) {
    for (int jc = 0; jc < N; jc += NC) {
        int n_block = (N - jc < NC) ? N - jc : NC;
        for (int kc = 0; kc < K; kc += KC) {
            int k_block = (K - kc < KC) ? K - kc : KC;
            pack_B_block(k_block, n_block, &B[kc + jc * K], K, packB);
            for (int ic = 0; ic < M; ic += MC) {
                int m_block = (M - ic < MC) ? M - ic : MC;
                pack_A_block(m_block, k_block, &A[ic + kc * M], M, packA);
                for (int jr = 0; jr < n_block; jr += NR) {
                    for (int ir = 0; ir < m_block; ir += MR) {
                        dgemm_micro_kernel(k_block, &packA[ir * k_block], &packB[jr * k_block], &C[(ic + ir) + (jc + jr) * M], M);
                    }
                }
            }
        }
    }
}

int main(int argc, char *argv[]) {
    int dim = 16;
    if (argc > 1) {
        dim = atoi(argv[1]);
        if (dim > MAX_DIM) dim = MAX_DIM;
    }

    double static_C[MAX_DIM * MAX_DIM];
    double *A = static_A;
    double *B = static_B;
    double *C = static_C;

    for (int i = 0; i < dim * dim; i++) {
        A[i] = (double)i / 100.0;
        B[i] = (double)(dim * dim - i) / 100.0;
        C[i] = 0.0;
    }

    dgemm_goto(dim, dim, dim, A, B, C);

    printf("Finished DGEMM.\n");
    printf("Address of matrix C: %p\n", (void*)C);
    printf("Matrix C (%dx%d):\n", dim, dim);

    for (int i = 0; i < dim; i++) {
        printf("Row %2d: ", i);
        for (int j = 0; j < dim; j++) {
            // Matrix is stored in column-major based on dgemm_goto logic
            printf("%8.4f ", C[i + j * dim]);
        }
        printf("\n");
    }

    return 0;
}

.arch armv8-a
.text
.align 2
.global userspace_entry

userspace_entry:
    adrp x0, matA
    add  x0, x0, :lo12:matA

    adrp x1, matB
    add  x1, x1, :lo12:matB

    ldr d1, [x0]        // A[0][0]
    ldr d2, [x1]        // B[0][0]
    fmul d3, d1, d2

    ldr d1, [x0, #8]    // A[0][1]
    ldr d2, [x1, #16]   // B[1][0]
    fmul d4, d1, d2

    fadd d0, d3, d4

    ret

.size userspace_entry, .-userspace_entry

.data
.align 8

.type matA, %object
.size matA, 32
matA:
    .double 1.0, 2.0
    .double 3.0, 4.0

.type matB, %object
.size matB, 32
matB:
    .double 5.0, 6.0
    .double 7.0, 8.0

.section .note.GNU-stack,"",@progbits

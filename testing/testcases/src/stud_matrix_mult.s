.arch armv8-a
.text
.align 2
.global userspace_entry

userspace_entry:
    // Load base addresses
    adrp x0, matA
    add  x0, x0, :lo12:matA

    adrp x1, matB
    add  x1, x1, :lo12:matB

    // Load A[0][0], A[0][1]
    ldur d0, [x0, #0]   
    ldur d1, [x0, #8]     

    // Load B[0][0], B[1][0]
    ldur d2, [x1, #0]     
    ldur d3, [x1, #16]    

    
    fmul d4, d0, d2

    fmul d5, d1, d3

    // Add results
    fadd d0, d4, d5

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

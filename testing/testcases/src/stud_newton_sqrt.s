        .arch armv8-a
        .text
        .align  2
        .p2align 3,,7
.global userspace_entry

userspace_entry:

    // compute sqrt(25)

    adrp x10, .consts
    add x10, x10, :lo12:.consts


    ldur d0, [x10]     // a
    ldur d1, [x10]     // x
    ldur d4, [x10, #8]

    movz x2, #6

.loop:
    cmp x2, #0
    b.eq .done

    ldur d5 [x10, #16]
    fmul d2, d0, d5    // a * approx(1/x)

    fadd d3, d1, d2
    fmul d1, d3, d4

    subs x2, x2, #1
    b .loop

.done:
    fmov d0, d1
    ret

.data
.align 8

.consts:
    .double 25.0
    .double 0.5
    .double 0.04

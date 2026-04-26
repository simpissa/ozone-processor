        .arch armv8-a
        .text
        .align  2
        .p2align 3,,7
.global userspace_entry

userspace_entry:

    // compute sqrt(25)

    fmov d0, #25.0     // a
    fmov d1, #25.0     // x
    fmov d4, #0.5

    movz x2, #6

.loop:
    cmp x2, #0
    b.eq .done

    fmov d5, #0.04
    fmul d2, d0, d5    // a * approx(1/x)

    fadd d3, d1, d2
    fmul d1, d3, d4

    subs x2, x2, #1
    b .loop

.done:
    fmov d0, d1
    ret

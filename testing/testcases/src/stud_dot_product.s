opal$ cat stud_dot_product.s
        .arch armv8-a
        .text
        .align  2
        .p2align 3,,7
.global userspace_entry

userspace_entry:

    adrp x0, .A
    add  x0, x0, :lo12:.A

    adrp x1, .B
    add  x1, x1, :lo12:.B

    movz x2, #5

    adrp x10, .consts
    add x10, x10, :lo12:.consts
    ldur d0, [x10]

.loop:
    cmp x2, #0
    b.eq .done

    ldur d1, [x0]
    ldur d2, [x1]

    fmul d3, d1, d2
    fadd d0, d0, d3

    add x0, x0, #8
    add x1, x1, #8
    subs x2, x2, #1

    b .loop

.done:
    ret


.data
.align 8

.A:
    .double 1.0
    .double 2.0
    .double 3.0
    .double 4.0
    .double 5.0

.B:
    .double 2.0
    .double 2.0
    .double 2.0
    .double 2.0
    .double 2.0

.consts:
    .double 0.0

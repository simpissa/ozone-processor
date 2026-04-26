        .arch armv8-a
        .text
        .align  2
        .p2align 3,,7
.global userspace_entry

userspace_entry:

    adrp x0, .A
    add  x0, x0, :lo12:.A

    movz x1, #0
    movz x2, #5

.loop:
    cmp x2, #0
    b.eq .done

    ldur x3, [x0]
    add  x1, x1, x3

    add  x0, x0, #8
    subs x2, x2, #1

    b .loop

.done:
    mov x0, x1
    ret


.data
.align 8

.A:
    .xword 10
    .xword 20
    .xword 30
    .xword 40
    .xword 50

.arch armv8-a
.text
.align 2
.global userspace_entry

userspace_entry:
    adrp x0, weights
    add  x0, x0, :lo12:weights

    adrp x1, values
    add  x1, x1, :lo12:values

    fmov d0, #0.0
    mov x2, #0

loop:
    cmp x2, #10
    bge done

    ldr d1, [x0, x2, lsl #3]   // load double directly
    ldr d2, [x1, x2, lsl #3]

    fmul d3, d1, d2
    fadd d0, d0, d3

    add x2, x2, #1
    b loop

done:
    ret

.size userspace_entry, .-userspace_entry

.data
.align 8

.type weights, %object
.size weights, 80
weights:
    .double 10.0, 2.0, 6.0, 4.0, 7.0
    .double 5.0, 6.0, 7.0, 8.0, 2.0

.type values, %object
.size values, 80
values:
    .double 3.0, 10.0, 3.0, 9.0, 3.0
    .double 3.0, 4.0, 8.0, 7.0, 8.0

.section .note.GNU-stack,"",@progbits

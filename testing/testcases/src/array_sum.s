.arch armv8-a
.text
.align 2
.global userspace_entry

userspace_entry:
    adrp x0, arr
    add  x0, x0, :lo12:arr   // base pointer

    mov x1, #0      // i = 0
    mov x2, #0      // sum = 0

loop:
    cmp x1, #10
    bge done

    ldr x3, [x0, x1, lsl #3]   // load arr[i]
    add x2, x2, x3

    add x1, x1, #1
    b loop

done:
    mov x0, x2      // return sum
    ret

.size userspace_entry, .-userspace_entry

.data
.align 8

.type arr, %object
.size arr, 80
arr:
    .xword 1
    .xword 2
    .xword 3
    .xword 4
    .xword 5
    .xword 6
    .xword 7
    .xword 8
    .xword 9
    .xword 10

.section .note.GNU-stack,"",@progbits

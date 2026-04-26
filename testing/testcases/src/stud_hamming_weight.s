.arch armv8-a
.text
.align 2
.global userspace_entry

userspace_entry:
    // Input value
    movz x0, #0xF0F0        // lower 16 bits
    movk x0, #0xF0F0, lsl #16
    movk x0, #0xF0F0, lsl #32
    movk x0, #0xF0F0, lsl #48   // x0 = 0xF0F0F0F0F0F0F0F0

    mov x1, #0      // count = 0

loop:
    cmp x0, #0
    b.eq done

    ands x2, x0, #1   // check lowest bit
    b.eq skip

    add x1, x1, #1    // increment count

skip:
    lsr x0, x0, #1    // shift right
    b loop

done:
    mov x0, x1        // return count
    ret

.size userspace_entry, .-userspace_entry
.section .note.GNU-stack,"",@progbits

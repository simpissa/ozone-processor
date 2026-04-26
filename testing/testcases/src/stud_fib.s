.arch armv8-a
.text
.align 2
.global userspace_entry
userspace_entry:
    mov x0, #0      // a = 0
    mov x1, #1      // b = 1
    mov x2, #20     // n

fib_loop:
    cmp x2, #0
    b.eq done
    add x3, x0, x1
    mov x0, x1
    mov x1, x3
    sub x2, x2, #1
    b fib_loop

done:
    mov x0, x0
    ret
.size userspace_entry, .-userspace_entry

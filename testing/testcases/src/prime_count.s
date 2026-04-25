.arch armv8-a
.text
.align 2
.global userspace_entry
userspace_entry:
    mov x0, #0          // count
    mov x1, #2          // curr num 

outer_loop:
    mov x2, #2          
    mov x3, #1          // is_prime = 1

check_loop:
    mul x4, x2, x2
    cmp x4, x1
    bgt is_prime_done

    udiv x5, x1, x2
    mul x6, x5, x2
    cmp x6, x1
    bne not_divisible

    mov x3, #0          // not prime
    b is_prime_done

not_divisible:
    add x2, x2, #1
    b check_loop

is_prime_done:
    cbz x3, skip_inc
    add x0, x0, #1

skip_inc:
    add x1, x1, #1
    cmp x1, #100
    ble outer_loop

    ret
.size userspace_entry, .-userspace_entry

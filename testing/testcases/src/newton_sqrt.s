.arch armv8-a
.text
.align 2
.global userspace_entry
userspace_entry:
    fmov d0, #25.0   // S
    fmov d1, #5.0    // initial guess

    mov x0, #10      // iterations

loop:
    cbz x0, done

    fdiv d2, d0, d1
    fadd d2, d2, d1
    fmov d3, #0.5
    fmul d1, d2, d3

    sub x0, x0, #1
    b loop

done:
    fmov d0, d1
    ret
.size userspace_entry, .-userspace_entry

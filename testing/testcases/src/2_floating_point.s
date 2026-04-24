.text
.global userspace_entry
userspace_entry:
    // 1. GPR -> Memory -> FP Register Communication
    // Load bit pattern for 2.0 (0x4000000000000000) into X0
    movz x0, #0x4000, lsl #48
    
    // Store X0 to stack
    sub  sp, sp, #16
    stur x0, [sp, #0]
    
    // Load into D0 from stack
    ldur d0, [sp, #0]
    
    // 2. FMOV: Load another constant (1.5 = 0x3FF8000000000000)
    // We'll use another GPR path for this to verify consistency
    movz x1, #0x3FF8, lsl #48
    stur x1, [sp, #8]
    ldur d1, [sp, #8]
    
    // 3. FADD: D2 = D0 + D1 (2.0 + 1.5 = 3.5)
    fadd d2, d0, d1
    
    // 4. FSUB: D3 = D2 - D1 (3.5 - 1.5 = 2.0)
    fsub d3, d2, d1
    
    // 5. FMUL: D4 = D3 * D0 (2.0 * 2.0 = 4.0)
    fmul d4, d3, d0
    
    // 6. FNEG: D5 = -D4 (-4.0)
    fneg d5, d4
    
    // 7. FCMP: Compare D4 and D3 (4.0 vs 2.0)
    fcmp d4, d3
    
    // Check flags (4.0 > 2.0, so should be Greater Than / HI)
    // If successful, set X0 to 0xABCD
    b.gt .Lmatch
    movz x0, #0xdead
    b .Lexit
.Lmatch:
    movz x0, #0xabcd

.Lexit:
    add sp, sp, #16
    // Final userspace instruction: RET to 0x0
    movz x30, #0
    ret

.section .text.boot
.global start
start:
    // Load config data base address
    adrp x10, _CONFIG_START
    add  x10, x10, :lo12:_CONFIG_START

    // 1. Set SP_EL0
    ldur x0, [x10, #0]
    msr  sp_el0, x0

    // 2. Set SPSR_EL1 (Target EL0)
    ldur x0, [x10, #24]
    msr  spsr_el1, x0

    // 3. Set ELR_EL1 (Userspace entry point)
    ldur x0, [x10, #32]
    msr  elr_el1, x0

    // 4. Set VBAR_EL1
    ldur x0, [x10, #16]
    msr  vbar_el1, x0

    // 5. Populate Page Table at TTBR0_EL1
    ldur x1, [x10, #40]      // _TTBR0_EL1
    
    ldur x2, [x10, #32]      // userspace_entry (_ELR_EL1)
    ldur x0, [x10, #0]       // SP_EL0
    
    // Find lowest page base using allowed instructions (CMP + B.cond)
    cmp  x2, x0
    b.lo .Luse_entry
    mov  x2, x0
.Luse_entry:
    and  x2, x2, #~0xfff     // Align to page base
    
    // Calculate table index for this starting page
    lsr  x3, x2, #12         // VPN
    lsl  x3, x3, #3          // Offset (VPN * 8)
    add  x1, x1, x3          // TTE address in table
    
    movz x3, #0
    ldur x4, [x10, #56]      // _NUM_STACK_PAGES
.Lfill_pt:
    orr  x5, x2, #1          // Set valid bit (Bit 0), PA=VA (direct map)
    stur x5, [x1, #0]
    add  x1, x1, #8
    add  x2, x2, #4096
    add  x3, x3, #1
    cmp  x3, x4
    b.ne .Lfill_pt

    // 6. Set initial LR for userspace to 0 (terminate on RET)
    movz x30, #0

    // 7. ERET to Userspace
    eret

.section .exception_vectors, "ax"
.align 11
.global exception_vector_table
exception_vector_table:
    .org 0x400
sync_handler:
    adrp x10, _CONFIG_START
    add  x10, x10, :lo12:_CONFIG_START
    // Write terminate value to ACTLR_EL1
    ldur x0, [x10, #48]
    msr  actlr_el1, x0
.Lspin:
    b .Lspin

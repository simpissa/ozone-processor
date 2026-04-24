.text
.global userspace_entry
userspace_entry:
    movz x0, #123
    
    // Attempt to access unmapped memory (e.g., 1MB offset from start of userspace)
    // The bootloader only maps _NUM_STACK_PAGES (currently 512KB).
    // Accessing 1MB will trigger a Load Page Fault.
    
    adrp x10, _CONFIG_START
    add  x10, x10, :lo12:_CONFIG_START
    ldur x1, [x10, #32] // Userspace Entry (_ELR_EL1)
    
    movz x2, #0x10
    lsl  x2, x2, #16  // x2 = 0x100000 (1MB)
    add  x1, x1, x2   // x1 = Userspace Entry + 1MB
    ldur x2, [x1, #0] // This should cause a Load Page Fault
    
    // Should not reach here
    movz x30, #0
    ret

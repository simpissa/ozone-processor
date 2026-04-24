	.arch armv8-a
	.text
	.align	2
	.p2align 3,,7
.global userspace_entry
userspace_entry:
    // Simple tests for the movz instruction.
    // Keep in mind all registers userspace_entry at 0.
    movz x0, #0x1234
    movz x1, #0x5678, lsl 16
    movz x2, #0x90AB, lsl 32
    movz x3, #0xCDEF, lsl 48
    movz x0, #0x5678, lsl 16
    movz x1, #0x90AB, lsl 32
    movz x2, #0xCDEF, lsl 48
	movz x3, #0x1234
    movz x0, #0x90AB, lsl 32
    movz x1, #0xCDEF, lsl 48
	movz x2, #0x1234
    movz x3, #0x5678, lsl 16
    movz x0, #0xCDEF, lsl 48
	movz x1, #0x1234
    movz x2, #0x5678, lsl 16
    movz x3, #0x90AB, lsl 32
	ret
	.size	userspace_entry, .-userspace_entry
	.ident	"GCC: (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0"
	.section	.note.GNU-stack,"",@progbits

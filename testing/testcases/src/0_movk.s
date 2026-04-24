	.arch armv8-a
	.text
	.align	2
	.p2align 3,,7
.global userspace_entry
userspace_entry:
    // Simple tests for the movk instruction.
    // Keep in mind all registers userspace_entry at 0.
    movk x0, #0x1234
    movk x1, #0x5678, lsl 16
    movk x2, #0x90AB, lsl 32
    movk x3, #0xCDEF, lsl 48
    movk x0, #0x5678, lsl 16
    movk x1, #0x90AB, lsl 32
    movk x2, #0xCDEF, lsl 48
	movk x3, #0x1234
    movk x0, #0x90AB, lsl 32
    movk x1, #0xCDEF, lsl 48
	movk x2, #0x1234
    movk x3, #0x5678, lsl 16
    movk x0, #0xCDEF, lsl 48
	movk x1, #0x1234
    movk x2, #0x5678, lsl 16
    movk x3, #0x90AB, lsl 32
	ret
	.size	userspace_entry, .-userspace_entry
	.ident	"GCC: (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0"
	.section	.note.GNU-stack,"",@progbits

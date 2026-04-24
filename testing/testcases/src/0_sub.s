	.arch armv8-a
	.text
	.align	2
	.p2align 3,,7
.global userspace_entry
userspace_entry:
    // Simple tests for the sub instruction.
    sub x0, x0, #1
    sub x1, x1, #0xfff
    sub x4, x0, #1
	ret
	.size	userspace_entry, .-userspace_entry
	.ident	"GCC: (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0"
	.section	.note.GNU-stack,"",@progbits

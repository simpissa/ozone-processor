	.arch armv8-a
	.file	"c_template.c"
	.text
	.align	2
	.global	userspace_entry
	.type	userspace_entry, %function
.global userspace_entry
userspace_entry:
.LFB1:
	.cfi_startproc
	sub sp, sp, #16
	stur x29, [sp]
	stur x30, [sp, #8]
	.cfi_def_cfa_offset 16
	.cfi_offset 29, -16
	.cfi_offset 30, -8
	add     x29, sp, #0
	movz	x1, 1000
	movz	x0, 100
	bl	add_two_nums
	movz	x1, 0
	ldur x30, [sp, #8]
	ldur x29, [sp]
	add sp, sp, #16
	.cfi_restore 30
	.cfi_restore 29
	.cfi_def_cfa_offset 0
	ret
	.cfi_endproc
.LFE1:
	.size	userspace_entry, .-userspace_entry
	.align	2
	.global	add_two_nums
	.type	add_two_nums, %function
add_two_nums:
.LFB0:
	.cfi_startproc
	adds	x0, x0, x1
	ret
	.cfi_endproc
.LFE0:
	.size	add_two_nums, .-add_two_nums
	.ident	"GCC: (Ubuntu 13.2.0-23ubuntu4) 13.2.0"
	.section	.note.GNU-stack,"",@progbits

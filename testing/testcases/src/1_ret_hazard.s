 	.arch armv8-a
	.text
	.align	2
.global userspace_entry
userspace_entry:

    // ret hazard -- check cycle count to ensure that it is stalling for ret pc

    movz x0, #10
    movz x1, #15
    // preserve the ret addr
    movz x2, #0
    adds x2, x30, x2
    bl helper
    // put the saved ret addr back in
    movz x30, #0
    adds x30, x2, x30

    adds x0, x0, x1

    // Print x0
    // correct: 113
    eor 	x5, x5, x5
	mvn 	x5, x5
	stur	x0, [x5]
	ret
	.size	userspace_entry, .-userspace_entry

helper:
    movz x0, #85
    movz x1, #28
    ret

    .size helper, .-helper
	.ident	"GCC: (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0"
	.section	.note.GNU-stack,"",@progbits

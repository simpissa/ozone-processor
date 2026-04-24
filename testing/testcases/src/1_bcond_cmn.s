	.arch armv8-a
	.text
	.align	2
.global userspace_entry
userspace_entry:

    movz x0, #0x7000, lsl #48
    movz x1, #0x4000, lsl #48
    cmn x0, x1
    b.vs .willoverflow

.goback:

    // Print x0
    eor 	x5, x5, x5
	mvn 	x5, x5
    //correct value is 7000000000000019
    //incorrect value is 7000000000000000
    //NZCV should be N, V (overflow when adding +s, resulting in negative)
	stur	x0, [x5]
	ret
	
.willoverflow:
    add x0, x0, #13
    add x0, x0, #12
    b .goback

    .size	userspace_entry, .-userspace_entry
	.ident	"GCC: (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0"
	.section	.note.GNU-stack,"",@progbits

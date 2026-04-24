	.arch armv8-a
	.text
	.align	2
.global userspace_entry
userspace_entry:
    // branch taken -- correct cycle count, etc.
    movz x0, #1
    movz x1, #1
    subs x3, x0, x1
    b.eq .helper

.goback:
    // Print x0
    // correct: 65535
    eor 	x5, x5, x5
	mvn 	x5, x5
	stur	x0, [x5]
	ret
	
.helper:
    movz x0, #65535
    movz x1, #42069
    b .goback

    .size	userspace_entry, .-userspace_entry
	.ident	"GCC: (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04) 7.5.0"
	.section	.note.GNU-stack,"",@progbits

.arch armv8-a
.text
.global userspace_entry
.align	2
.global userspace_entry
userspace_entry:
    // x1 is stack pointer
    // x2 is limit
    // x3 is counter
    // x4 is junk register (no xzr)
    // x7 has temporary values

    EOR x1, x1, x1
    ADD x1, sp, #0
    MOVZ x7, #16
    SUBS x1, x1, x7
    EOR x2, x2, x2
    MOVZ x7, #27
    ADDS x2, x2, x7
    EOR x3, x3, x3
    ADD x3, x3, #1
    MOVZ x7, #16

    // loop
.INPUT_LOOP:
    SUBS x4, x3, x2
    B.EQ .START_SUM
    STUR x3, [x1]
    ADD x3, x3, #1
    SUBS x1, x1, x7
    B .INPUT_LOOP

.START_SUM:
    // x0 is running sum (and eventual result)
    // x1 is stack pointer
    // x2 is load destination
    // x3 is counter
    // x4 is junk register (no xzr)
    // x5 is stack pointer for x30 saves
    // x6 is x30 save load destination

    EOR x0, x0, x0
    EOR x2, x2, x2
    EOR x3, x3, x3
    MOVZ x7, #26
    ADDS x3, x3, x7
	RET

	.size	userspace_entry, .-userspace_entry
    .align 2


recursive:

    // x0 is running sum (and eventual result)
    // x1 is stack pointer
    // x2 is load destination
    // x3 is counter
    // x4 is junk register (no xzr)
    // x5 is stack pointer for x30 saves
    // x6 is x30 save load destination

    // prologue, set up stack stuff
    MOVZ x7, #16
    SUBS x5, x5, x7
    STUR x30, [x5]

    EOR x7, x7, x7
    SUBS x4, x3, x7
    B.EQ .BASE_CASE


    ADD x1, x1, #16
    LDUR x2, [x1]
    ADDS x0, x0, x2
    EOR x2, x2, x2
    MOVZ x9, #1
    SUBS x3, x3, x9
    BL recursive

.BASE_CASE:
    LDUR x30, [x5]
    ADD x5, x5, #16
    RET
    NOP // padding ... null pointer read issue
    NOP
    NOP

.size recursive, .-recursive

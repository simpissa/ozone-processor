.text
.global start
start:
    b userspace_entry
    // If it returns, terminate machine (X30 was already 0)
    ret

// This file is linked with programs which run in EL0 only. It's only really
// useful for testing purposes, if you're trying to run without EL1 support or
// something.

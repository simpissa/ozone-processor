.arch armv8-a
.text
.global userspace_entry

.align  2
.p2align 3,,7
.global userspace_entry
.type   userspace_entry, %function

//This function goes through the array sorted array and performs binary search to find the target

.global userspace_entry
userspace_entry:

    adrp    x0, .array       // Load address of the array
    add     x0, x0, :lo12:.array
    movz    x1, #10        
    movz    x2, #7        

    movz x3, #0 // initialization of left
    movz x4, #0 // initialization of right
    sub x4, x1, #1 //right = size - 1

.loop:
    cmp x3, x4
    b.gt .end
    movz x5, #0 //initialization of mid
    subs x5, x4, x3 //mid = right - left
    asr x5, x5, #1 // mid = (right - left) /2
    adds x5, x3, x5 //mid = left + (right - left) /2

    lsl  x7, x5, #3   // x7 = x5 * 8 (shift left by 2)
    adds  x6, x0, x7   // x6 = x0 + x7
    ldur  x7, [x6, #0]
    movz  x9, 0xffff  
    lsl   x9, x9, #16  
    movk  x9, 0xffff  
    ands  x7, x7, x9

    cmp x7, x2 //compare array[mid] to target
    b.eq .returnMid
    b.ge .decRight
    add x3, x5, #1
    b .loop

.returnMid:
    //once we find the target return
    subs x0, x0, x0
    adds x0, x0, x5
    ret

.decRight:
    sub x4, x5, #1
    b .loop

.end:
    movz x0, #0
    sub x0, x0, #1
    ret



.size   userspace_entry, .-userspace_entry
// ... and ends with the .size above this line.

.data
.align 8
.type array, %object
.size array, 80

.array:
    .xword 1
    .xword 3
    .xword 5
    .xword 7
    .xword 9
    .xword 11
    .xword 13
    .xword 15
    .xword 17
    .xword 19
    

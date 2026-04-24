.global	userspace_entry
.type	userspace_entry, %function
.global userspace_entry
userspace_entry:
	sub		sp, sp, 256
	mvn		x7, xzr

    adrp 	x1, .weights
	add		x1, x1, :lo12:.weights
	adrp 	x2, .values
	add		x2, x2, :lo12:.values

// loop to set zeroes to the array of 26 bytes
	add		x0, sp, 0
	add		x5, x0, 208
	b 		.zero_loop_chk
.zero_loop_body:
	stur	xzr, [x0]
	add		x0, x0, 8
.zero_loop_chk:
	cmp		x0, x5
	b.ne	.zero_loop_body

// prep outer loop, j
	movz	x3, 0        // j = 0
	b		.j_loop_chk
.j_loop_body:
	// set up i loop
	movz	x4, 26       // decremented in body to actual value
	b		.i_loop_chk

.i_loop_body:
	sub		x4, x4, 1           // decrement i to actual value
	// load weights[j] into x0
	// first prep address of weights[j] in x0
	// x0 = .weights + 8j
	lsl		x0, x3, 3  // x0 = 8*j
	adds	x0, x0, x1 // x0 = .weights + 8j
	ldur	x0, [x0]   // x0 = weights[j]

	// if i < weights[j], skip this iteration
	subs	x0, x4, x0		// x0 has i - weights[j]
	b.lt	.i_loop_chk		// if i < weights[j] continue

	// else, dp[i] = max(dp[i], dp[i - weights[j]] + values[j]);
	// first get dp[i - weights[j]] + values[j]
	// x0 holds i - weights[j]
	// now index into dp using that as the offset
	lsl		x0, x0, 3
	add		x5, sp, 0
	adds	x0, x0, x5
	ldur	x0, [x0]

	// now x0 has dp[i - weights[j]].
	// now we need to add values[j]
	lsl		x5, x3, 3
	adds	x5, x5, x2
	ldur	x5, [x5]
	adds	x0, x0, x5
	// now x0 has dp[i - weights[j]] + values[j]

	// now we need dp[i]
	// let's get that into x6
	// and the pointer to dp[i] is in x5
	add		x5, sp, 0
	lsl		x6, x4, 3
	adds	x5, x5, x6
	ldur 	x6, [x5]
	// now x6 has dp[i]
	// now we compare, then conditionally select
	cmp		x0, x6
	b.gt 	.keep_x0
	mov		x0, x6
.keep_x0:
	stur	x0, [x5]

.i_loop_chk:
	CMP		x4, xzr
	b.ne	.i_loop_body

	// increment j
	add		x3, x3, 1

.j_loop_chk:
	movz	x9, 10
	cmp		x3, x9
	b.lt .j_loop_body

	// return the last element of the dp array
	add		x0, sp, 200
	ldur	x0, [x0]
	stur 	x0, [x7]
	ret

.data
.align 8

.type weights, %object
.size weights, 80

.weights:
	.xword	10
	.xword	2
	.xword	6
	.xword	4
	.xword	7
	.xword	5
	.xword	6
	.xword	7
	.xword	8
	.xword	2

.type values, %object
.size values, 80
.values:
	.xword	3
	.xword	10
	.xword	3
	.xword	9
	.xword	3
	.xword	3
	.xword	4
	.xword	8
	.xword	7
	.xword	8

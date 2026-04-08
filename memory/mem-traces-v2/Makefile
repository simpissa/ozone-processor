clean:
	$(RM) parse_trace replay_trace dgemm

parse_trace: parse_trace.c
	gcc -O3 parse_trace.c -o parse_trace

replay_trace: replay_trace.c
	gcc -O3 replay_trace.c -o replay_trace

dgemm: dgemm.c
	gcc -O3 dgemm.c -o dgemm -static -fno-stack-protector

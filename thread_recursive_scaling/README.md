# Thread Recursive Scaling

This experiment recursively creates pthreads in a tree structure to observe scalability and system limits.

Files:
- `thread_recursive.c` — recursive thread creator.
- `run_thread_recursive.sh` — compile + example run script.

Compile:

```sh
gcc -O2 -pthread -o thread_recursive thread_recursive.c -lm
```

Run (examples):

```sh
# Branching factor 2, depth 6, hold leaves 30s
./thread_recursive -b 2 -d 6 -s 30

# Higher branching (DO NOT USE ON MAIN MACHINE)
./thread_recursive -b 4 -d 5 -s 60
```

Notes:
- The program estimates the full-tree size and prints the actual number of threads created.
- Use conservative parameters on shared systems. High branching+depth grows exponentially.

# Thread Recursive Scaling

This experiment recursively creates pthreads in a tree structure to observe scalability and system limits.

Files:
- `thread_recursive.c` — recursive thread creator.
- `run_thread_recursive.sh` — compile + run + metrics recording script.

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

Automated run + recording:

```sh
# Uses defaults: branch=2 depth=6 hold=10
bash run_thread_recursive.sh

# Custom parameters
bash run_thread_recursive.sh 2 6 20
```

Recorded artifacts:
- `runs/<run_id>_stdout.log` — program stdout.
- `runs/<run_id>_stderr.log` — program stderr.
- `runs/<run_id>_samples.csv` — 1s samples: elapsed seconds, CPU%, RSS, VSZ, thread count.
- `results.csv` — one summary row per run.

`results.csv` columns:
- `run_id,timestamp,host,kernel,branch,depth,hold_s,exit_code,wall_s,max_rss_kb,max_vsz_kb,max_threads,avg_cpu,max_cpu,total_created_threads,estimated_full_tree`

Notes:
- The program estimates the full-tree size and prints the actual number of threads created.
- Use conservative parameters on shared systems. High branching+depth grows exponentially.

# Fork vs Threads Project Synopsis

## Project Synopsis

This project investigates the differences between process creation using fork() and thread creation  
using pthreads in Linux. The goal is to experimentally evaluate performance, scalability, and  
system limits. By measuring execution time, memory usage, and maximum creation limits, we aim  
to understand how the operating system balances efficiency and isolation.

## Workload Distribution (4 Members)

- **Ηλίας –** Theory & Background + CITATIONS!!!!: Write introduction and explain  
    processes vs threads concepts.
- **Ανδρέας & Διονύσης –** Experiment & Code: Implement all benchmarks and run  
    experiments.
- **Αντώνης –** Data & Visualization: Collect results and create graphs/tables.
- **Ανδρέας & Διονύσης –** Analysis & Writing + CITATIONS!!!!: Write methodology,  
    discussion, and conclusion sections.

## Experiments Overview

- [x] Creation Time Comparison:  
    Measures how long it takes to create multiple processes using fork() versus threads  
    using pthreads. This highlights the overhead differences between process and thread  
    creation.
- [ ] Recursive Fork Explosion:  
    A process recursively calls fork() to observe exponential growth in the number of  
    processes. This demonstrates how quickly system resources can be exhausted.
- [x] Thread Recursive Scaling:  
    Similar recursive creation using threads to compare scalability and resource usage against  
    fork().
- [x] Maximum Limit Stress Test:  
    Continuously creates processes or threads until the system refuses further creation,  
    revealing OS-enforced limits on concurrency.
- [ ] Memory and Stability Observation(removed max forks with ulimit -u 20000):  
    Monitors system memory usage and system responsiveness during heavy process and  
    thread creation.

## Key Findings Focus

- Threads are expected to be faster and more scalable than processes. - fork() is heavier due to  
    process isolation. - Recursive fork leads to exponential growth and system stress. - Threads share  
    memory, reducing overhead but increasing complexity. - System limits prevent uncontrolled  
    resource exhaustion.

PS. See undefined behaviour from calling fork inside thread.  
Print stack on each fork bomb on each iteration.  
Citations will include:

1.  Man pages
2.  Linux kernel docs from IEEE
3.  Thread docs


## Key Commands for lifting linux kernel restrictions on alpine linux for threads & processes:

```
# Lift shell nproc limit
ulimit -u unlimited

# Raise kernel PID/thread caps (temporary until reboot)
sudo sysctl -w kernel.pid_max=131072
sudo sysctl -w kernel.threads-max=131072

# Lift cgroup v2 pids limit (temporary until reboot)
sudo sh -c 'echo max > /sys/fs/cgroup/pids.max'
```

## Crash/Stress Behavior (Runner Env Vars)

The runner script uses the following environment variables to control risky experiments:

- `ALLOW_DANGEROUS=1` to enable `fork_bomb` and `max_limit_stress` (default: 0).
- `FORK_BOMB_SECONDS=<seconds>` to timebox `fork_bomb` runtime.
- `MAX_LIMIT_SECONDS=<seconds>` to timebox `max_limit_stress` runtime.

Example:

```sh
ALLOW_DANGEROUS=1 FORK_BOMB_SECONDS=5 MAX_LIMIT_SECONDS=5 bash run_all_experiments.sh
```
#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN_ID=$(date +"%Y%m%d_%H%M%S")
OUT_DIR="$ROOT_DIR/experiment_runs/$RUN_ID"
mkdir -p "$OUT_DIR"

LOG_FILE="$OUT_DIR/activity.log"

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

count_processes() {
  ls /proc | awk '/^[0-9]+$/' | wc -l
}

count_threads_total() {
  awk '/^Threads:/ {sum+=$2} END {print sum+0}' /proc/[0-9]*/status 2>/dev/null || echo 0
}

get_mem_kb() {
  awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print t" "a}' /proc/meminfo
}

sample_process_csv() {
  local pid="$1"
  local csv="$2"
  local start_uptime="$3"
  local max_seconds="$4"

  local clk_tck
  clk_tck=$(getconf CLK_TCK)

  local prev_uptime prev_ticks
  prev_uptime=$(awk '{print $1}' /proc/uptime)
  prev_ticks=0
  if [ -r "/proc/$pid/stat" ]; then
    prev_ticks=$(awk '{print $14 + $15}' "/proc/$pid/stat")
  fi

  while kill -0 "$pid" 2>/dev/null; do
    local now_uptime elapsed_s
    now_uptime=$(awk '{print $1}' /proc/uptime)
    elapsed_s=$(awk -v s="$start_uptime" -v n="$now_uptime" 'BEGIN{printf "%.3f", (n-s)}')

    if [ "$max_seconds" -gt 0 ]; then
      if awk -v e="$elapsed_s" -v m="$max_seconds" 'BEGIN{exit (e>m)?0:1}'; then
        log "Timeout reached (${max_seconds}s), stopping PID=$pid"
        kill -TERM "-$pid" 2>/dev/null || true
        sleep 2
        kill -KILL "-$pid" 2>/dev/null || true
        break
      fi
    fi

    local load1 load5 load15
    read -r load1 load5 load15 _ < /proc/loadavg

    local mem_total mem_avail mem_used
    read -r mem_total mem_avail < <(get_mem_kb || echo "0 0")
    mem_used=$((mem_total - mem_avail))

    local proc_count thread_total
    proc_count=$(count_processes || echo 0)
    thread_total=$(count_threads_total || echo 0)

    local rss=0 vsz=0 stk=0 heap=0 nlwp=0
    if [ -r "/proc/$pid/status" ]; then
      rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status")
      vsz=$(awk '/^VmSize:/ {print $2}' "/proc/$pid/status")
      stk=$(awk '/^VmStk:/ {print $2}' "/proc/$pid/status")
      heap=$(awk '/^VmData:/ {print $2}' "/proc/$pid/status")
      nlwp=$(awk '/^Threads:/ {print $2}' "/proc/$pid/status")
    fi

    local cur_ticks dt dc cpu
    cur_ticks=$prev_ticks
    if [ -r "/proc/$pid/stat" ]; then
      cur_ticks=$(awk '{print $14 + $15}' "/proc/$pid/stat")
    fi
    dt=$(awk -v a="$prev_uptime" -v b="$now_uptime" 'BEGIN{print b-a}')
    dc=$(awk -v a="$prev_ticks" -v b="$cur_ticks" 'BEGIN{print b-a}')
    cpu=$(awk -v dt="$dt" -v dc="$dc" -v hz="$clk_tck" 'BEGIN{ if (dt<=0) printf "0.00"; else printf "%.2f", (100.0*dc)/(dt*hz) }')

    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
      "$(date -Iseconds)" "$elapsed_s" "$load1" "$load5" "$load15" \
      "$mem_total" "$mem_avail" "$mem_used" "$proc_count" "$thread_total" \
      "$pid" "$cpu" "${rss:-0}" "${vsz:-0}" "${stk:-0}" "${heap:-0}" "${nlwp:-0}" \
      >> "$csv"

    prev_uptime=$now_uptime
    prev_ticks=$cur_ticks
    sleep 1
  done
}

run_with_sampling() {
  local name="$1"
  local cmd="$2"
  local csv="$3"
  local max_seconds="$4"

  log "Starting $name: $cmd"

  echo "timestamp,elapsed_s,load1,load5,load15,mem_total_kb,mem_available_kb,mem_used_kb,proc_count,thread_count_total,pid,cpu_pct,rss_kb,vsz_kb,stack_kb,heap_kb,proc_threads" > "$csv"

  local start_uptime pid
  start_uptime=$(awk '{print $1}' /proc/uptime)

  if command -v setsid >/dev/null 2>&1; then
    setsid bash -c "$cmd" &
    pid=$!
  else
    bash -c "$cmd" &
    pid=$!
  fi

  sample_process_csv "$pid" "$csv" "$start_uptime" "$max_seconds"

  set +e
  wait "$pid"
  local exit_code=$?
  set -e

  log "Finished $name (exit_code=$exit_code)"
}

compile_creation_time() {
  log "Compiling creation_time"
  gcc -O2 -pthread -o "$ROOT_DIR/creation_time_experiment/creation_time" \
    "$ROOT_DIR/creation_time_experiment/creation_time.c"
}

compile_fork_bomb() {
  log "Compiling fork_bomb"
  gcc -O2 -o "$ROOT_DIR/fork_bomb/fork_bomb" \
    "$ROOT_DIR/fork_bomb/fork_bomb.c"
}

compile_max_limit() {
  log "Compiling stress"
  gcc -O2 -o "$ROOT_DIR/Maximum_limit_stress_test/stress" \
    "$ROOT_DIR/Maximum_limit_stress_test/stress.c"
}

compile_thread_stress() {
  log "Compiling thread_stress"
  gcc -O2 -pthread -o "$ROOT_DIR/thread_stress_test/thread_stress" \
    "$ROOT_DIR/thread_stress_test/thread_stress.c"
}

compile_creation_time
compile_fork_bomb
compile_max_limit
compile_thread_stress

# Defaults (override by env vars)
ALLOW_DANGEROUS=${ALLOW_DANGEROUS:-0}
FORK_BOMB_SECONDS=${FORK_BOMB_SECONDS:-5}
MAX_LIMIT_SECONDS=${MAX_LIMIT_SECONDS:-5}
CREATION_TIME_ITERS=${CREATION_TIME_ITERS:-"100 1000 10000"}
CREATION_TIME_SECONDS=${CREATION_TIME_SECONDS:-60}

CREATION_TIME_STDOUT="$OUT_DIR/creation_time_stdout.log"
CREATION_TIME_STDERR="$OUT_DIR/creation_time_stderr.log"

run_with_sampling \
  "creation_time" \
  "cd '$ROOT_DIR/creation_time_experiment' && { for n in $CREATION_TIME_ITERS; do echo \"=== iterations=\$n ===\"; ./creation_time -n \"\$n\"; done; } >'$CREATION_TIME_STDOUT' 2>'$CREATION_TIME_STDERR'" \
  "$OUT_DIR/creation_time.csv" \
  "$CREATION_TIME_SECONDS"

if [ "$ALLOW_DANGEROUS" -eq 1 ]; then
  run_with_sampling \
    "fork_bomb" \
    "cd '$ROOT_DIR/fork_bomb' && ./fork_bomb" \
    "$OUT_DIR/fork_bomb.csv" \
    "$FORK_BOMB_SECONDS"
else
  log "Skipping fork_bomb (set ALLOW_DANGEROUS=1 to run)"
  echo "timestamp,elapsed_s,load1,load5,load15,mem_total_kb,mem_available_kb,mem_used_kb,proc_count,thread_count_total,pid,cpu_pct,rss_kb,vsz_kb,stack_kb,heap_kb,proc_threads" > "$OUT_DIR/fork_bomb.csv"
fi

if [ "$ALLOW_DANGEROUS" -eq 1 ]; then
  run_with_sampling \
    "max_limit_stress" \
    "cd '$ROOT_DIR/Maximum_limit_stress_test' && ./stress" \
    "$OUT_DIR/max_limit_stress.csv" \
    "$MAX_LIMIT_SECONDS"
else
  log "Skipping max_limit_stress (set ALLOW_DANGEROUS=1 to run)"
  echo "timestamp,elapsed_s,load1,load5,load15,mem_total_kb,mem_available_kb,mem_used_kb,proc_count,thread_count_total,pid,cpu_pct,rss_kb,vsz_kb,stack_kb,heap_kb,proc_threads" > "$OUT_DIR/max_limit_stress.csv"
fi

run_with_sampling \
  "thread_recursive_scaling" \
  "cd '$ROOT_DIR/thread_recursive_scaling' && ./run_thread_recursive.sh" \
  "$OUT_DIR/thread_recursive_scaling.csv" \
  0

run_with_sampling \
  "thread_stress" \
  "cd '$ROOT_DIR/thread_stress_test' && ./thread_stress" \
  "$OUT_DIR/thread_stress.csv" \
  0

log "All experiments finished"
log "Run directory: $OUT_DIR"

#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

gcc -O2 -pthread -o thread_recursive thread_recursive.c -lm

echo "Compiled thread_recursive"

# Usage:
#   ./run_thread_recursive.sh [branch] [depth] [hold_seconds]
# Example:
#   ./run_thread_recursive.sh 2 6 10

BRANCH=${1:-2}
DEPTH=${2:-6}
HOLD=${3:-10}

RESULTS_CSV="$DIR/results.csv"
RUNS_DIR="$DIR/runs"
mkdir -p "$RUNS_DIR"

RUN_ID=$(date +"%Y%m%d_%H%M%S")
STDOUT_LOG="$RUNS_DIR/${RUN_ID}_stdout.log"
STDERR_LOG="$RUNS_DIR/${RUN_ID}_stderr.log"
SAMPLE_LOG="$RUNS_DIR/${RUN_ID}_samples.csv"

if [ ! -f "$RESULTS_CSV" ]; then
	echo "run_id,timestamp,host,kernel,branch,depth,hold_s,exit_code,wall_s,max_rss_kb,max_vsz_kb,max_threads,avg_cpu,max_cpu,total_created_threads,estimated_full_tree" > "$RESULTS_CSV"
fi

echo "Running: ./thread_recursive -b $BRANCH -d $DEPTH -s $HOLD"

START_UPTIME=$(awk '{print $1}' /proc/uptime)
./thread_recursive -b "$BRANCH" -d "$DEPTH" -s "$HOLD" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
PID=$!

echo "Sampling metrics for PID=$PID (1s interval)"
echo "sec_from_start,cpu_pct,rss_kb,vsz_kb,nlwp" > "$SAMPLE_LOG"

MAX_RSS=0
MAX_VSZ=0
MAX_THR=0
MAX_CPU=0
SUM_CPU=0
SAMPLE_COUNT=0

CLK_TCK=$(getconf CLK_TCK)
PREV_UPTIME=$(awk '{print $1}' /proc/uptime)
PREV_TICKS=0
if [ -r "/proc/$PID/stat" ]; then
	PREV_TICKS=$(awk '{print $14 + $15}' "/proc/$PID/stat")
fi

while kill -0 "$PID" 2>/dev/null; do
	NOW_UPTIME=$(awk '{print $1}' /proc/uptime)
	ELAPSED_S=$(awk -v s="$START_UPTIME" -v n="$NOW_UPTIME" 'BEGIN{printf "%.3f", (n-s)}')

	if [ -r "/proc/$PID/status" ] && [ -r "/proc/$PID/stat" ]; then
		RSS=$(awk '/^VmRSS:/ {print $2}' "/proc/$PID/status")
		VSZ=$(awk '/^VmSize:/ {print $2}' "/proc/$PID/status")
		NLWP=$(awk '/^Threads:/ {print $2}' "/proc/$PID/status")
		CUR_TICKS=$(awk '{print $14 + $15}' "/proc/$PID/stat")

		RSS=${RSS:-0}
		VSZ=${VSZ:-0}
		NLWP=${NLWP:-0}

		DT=$(awk -v a="$PREV_UPTIME" -v b="$NOW_UPTIME" 'BEGIN{print b-a}')
		DC=$(awk -v a="$PREV_TICKS" -v b="$CUR_TICKS" 'BEGIN{print b-a}')
		CPU=$(awk -v dt="$DT" -v dc="$DC" -v hz="$CLK_TCK" 'BEGIN{ if (dt<=0) printf "0.00"; else printf "%.2f", (100.0*dc)/(dt*hz) }')

		echo "$ELAPSED_S,$CPU,$RSS,$VSZ,$NLWP" >> "$SAMPLE_LOG"

		MAX_RSS=$(awk -v a="$MAX_RSS" -v b="$RSS" 'BEGIN{print (b>a)?b:a}')
		MAX_VSZ=$(awk -v a="$MAX_VSZ" -v b="$VSZ" 'BEGIN{print (b>a)?b:a}')
		MAX_THR=$(awk -v a="$MAX_THR" -v b="$NLWP" 'BEGIN{print (b>a)?b:a}')
		MAX_CPU=$(awk -v a="$MAX_CPU" -v b="$CPU" 'BEGIN{print (b>a)?b:a}')
		SUM_CPU=$(awk -v s="$SUM_CPU" -v c="$CPU" 'BEGIN{print s+c}')
		SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

		PREV_UPTIME=$NOW_UPTIME
		PREV_TICKS=$CUR_TICKS
	fi
	sleep 1
done

set +e
wait "$PID"
EXIT_CODE=$?
set -e
END_UPTIME=$(awk '{print $1}' /proc/uptime)
WALL_S=$(awk -v s="$START_UPTIME" -v e="$END_UPTIME" 'BEGIN{printf "%.6f", (e-s)}')

AVG_CPU=0
if [ "$SAMPLE_COUNT" -gt 0 ]; then
	AVG_CPU=$(awk -v s="$SUM_CPU" -v n="$SAMPLE_COUNT" 'BEGIN{printf "%.2f", s/n}')
fi
MAX_CPU_FMT=$(awk -v m="$MAX_CPU" 'BEGIN{printf "%.2f", m}')

TOTAL_CREATED=$(grep -E "total_created_threads:" "$STDOUT_LOG" | awk -F': ' '{print $2}' | tail -n1)
ESTIMATED=$(grep -E "estimated_full_tree:" "$STDOUT_LOG" | awk -F': ' '{print $2}' | tail -n1)
TOTAL_CREATED=${TOTAL_CREATED:-NA}
ESTIMATED=${ESTIMATED:-NA}

TS=$(date +"%Y-%m-%dT%H:%M:%S%z")
HOST=$(hostname)
KERNEL=$(uname -r)

echo "$RUN_ID,$TS,$HOST,$KERNEL,$BRANCH,$DEPTH,$HOLD,$EXIT_CODE,$WALL_S,$MAX_RSS,$MAX_VSZ,$MAX_THR,$AVG_CPU,$MAX_CPU_FMT,$TOTAL_CREATED,$ESTIMATED" >> "$RESULTS_CSV"

echo
echo "Run complete"
echo "  stdout: $STDOUT_LOG"
echo "  stderr: $STDERR_LOG"
echo "  samples: $SAMPLE_LOG"
echo "  results csv: $RESULTS_CSV"
echo "  exit_code=$EXIT_CODE wall_s=$WALL_S max_rss_kb=$MAX_RSS max_threads=$MAX_THR avg_cpu=$AVG_CPU max_cpu=$MAX_CPU_FMT"

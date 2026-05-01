#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
results_file="$script_dir/creation_time_results.txt"
binary="$script_dir/creation_time"

: > "$results_file"
for n in 100 1000 10000 100000; do
    printf '\n=== iterations=%s ===\n' "$n" >> "$results_file"
    "$binary" -n "$n" >> "$results_file" 2>&1
done

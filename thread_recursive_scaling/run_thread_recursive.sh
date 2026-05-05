#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
cd "$DIR"

gcc -O2 -pthread -o thread_recursive thread_recursive.c -lm

echo "Compiled thread_recursive"

echo "Running sample: branch=2 depth=6 hold=20"
./thread_recursive -b 2 -d 6 -s 20

#!/bin/bash

set -e
# pipefail: without it, `run_benchmark.sh | tee` returns tee's (0) exit
# status, so a failed/crashed agent run was reported as "completed
# successfully". pipefail makes the pipeline surface run_benchmark.sh's failure.
set -o pipefail

# App identifiers: edgedelta (Edge Delta), bindplane (Bindplane), cribl (Cribl), otelcol (OpenTelemetry Collector)
app=$1
type=$2

if [[ -z "$app" ]]; then
  echo "Select app for benchmark:"
  select app in edgedelta bindplane cribl otelcol; do
    if [[ -n "$app" ]]; then
      break
    fi
    echo "Invalid selection. Try again."
  done
fi

log_dir="benchmark_results"
mkdir -p "$log_dir"

# Verify run_bench.sh exists and is executable
if [[ ! -x "./run_benchmark.sh" ]]; then
  echo "Error: run_benchmark.sh not found or not executable"
  exit 1
fi

echo "========================================="
echo "Running benchmark for $app - $type"
echo "========================================="
  
log_file="$log_dir/${app}_${type}.log"

if ./run_benchmark.sh "$app" | tee "$log_file"; then
  echo "Benchmark for $app - $type completed successfully"
else
  echo "Error: Benchmark for $app - $type failed (check $log_file for details)"
  exit 1
fi
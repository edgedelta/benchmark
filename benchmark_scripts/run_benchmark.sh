#!/bin/bash

set -e

app=$1
if [[ -z "$app" ]]; then
  echo "Missing app"
  exit 1
fi

if [[ "$app" == "edgedelta" ]]; then
  service="edgedelta.service"
  port=8085
elif [[ "$app" == "bindplane" ]]; then
  service="observiq-otel-collector"
  port=7075
elif [[ "$app" == "cribl" ]]; then
  service="cribl-edge.service"
  port=6085
else
  echo "Invalid app"
  exit 1
fi

# Cleanup function to ensure service is stopped on exit
cleanup() {
  sudo systemctl stop "$service" 2>/dev/null || true
}
trap cleanup EXIT ERR

# Start service
echo "Starting $service..."
if ! sudo systemctl start "$service"; then
  echo "Failed to start $service"
  exit 1
fi

# Wait for service to be ready
echo "Waiting for service to be ready..."
sleep 30

# Verify service is running
if ! sudo systemctl is-active --quiet "$service"; then
  echo "Service $service is not active after start"
  exit 1
fi

# Verify service port is listening (retry for up to 60 seconds)
echo "Checking that port $port is listening (up to 60s)..."
port_ready=false
for ((i=0; i<60; i++)); do
  if nc -z localhost "$port" 2>/dev/null; then
    echo "Port $port is listening on localhost"
    port_ready=true
    break
  fi
  sleep 1
done

if [[ "$port_ready" != true ]]; then
  echo "Port $port did not start listening on localhost within 60 seconds"
  exit 1
fi

for i in 80 100 120; do
  echo "Starting loadgen with ${i} workers for $app"
  
  # Get service PID
  if [[ "$app" == "cribl" ]]; then
    cribl_pid=$(ps aux | grep "[c]ribl.js" | awk '{print $2}')
    if [[ -z "$cribl_pid" ]]; then
      echo "Warning: Could not find cribl.js process"
    fi
    
    service_pid=$(ps aux | grep "[c]ribl server" | awk '{print $2}')
    if [[ -z "$service_pid" ]]; then
      echo "Warning: Could not find cribl server process"
    fi
    
    # Start monitor for cribl.js if PID found
    if [[ -n "$cribl_pid" ]]; then
      loadgen --monitor-pid "$cribl_pid" &
      cribl_monitor_pid=$!
    fi

    loadgen \
      --endpoint http://localhost:$port \
      --format nginx_log \
      --number 1 \
      --workers "$i" \
      --period 1ms \
      --total-time 1m \
      --monitor-self \
      --monitor-pid "${service_pid}"
    if [[ -n "$cribl_monitor_pid" ]]; then
      kill "$cribl_monitor_pid" 2>/dev/null || true
    fi
  elif [[ "$app" == "bindplane" ]]; then
    loadgen \
      --endpoint http://localhost:$port \
      --format nginx_log \
      --number 1 \
      --workers "$i" \
      --period 1ms \
      --total-time 1m \
      --monitor-self \
      --monitor-process "observiq"
  else
    loadgen \
      --endpoint http://localhost:$port \
      --format nginx_log \
      --number 1 \
      --workers "$i" \
      --period 1ms \
      --total-time 1m \
      --monitor-self \
      --monitor-process "${app}"
  fi

  echo "Finished loadgen with ${i} workers for $app"

  # Wait for 60 seconds before starting next iteration
  sleep 60
done
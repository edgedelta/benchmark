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
elif [[ "$app" == "cribl" ]]; then
  service="cribl-edge.service"
  port=6085
elif [[ "$app" == "otelcol" ]]; then
  service="otelcol-contrib.service"
  port=5085
elif [[ "$app" == "fluentd" ]]; then
  service="fluentd.service"
  port=3085
else
  echo "Invalid app"
  exit 1
fi

# loadgen endpoint. Fluentd's in_http derives the tag from the URL path, so it
# must be posted to a tagged path; everything else accepts the bare root.
endpoint="http://localhost:$port"
if [[ "$app" == "fluentd" ]]; then
  endpoint="http://localhost:$port/benchmark.fluentd"
fi

# Cleanup function to ensure service is stopped on exit
cleanup() {
  sudo systemctl stop "$service" 2>/dev/null || true
}
trap cleanup EXIT ERR

# On agent failure, dump diagnostics to stdout. The benchmark instance is torn
# down (terraform destroy) before result artifacts are uploaded, so evidence
# must be emitted inline here — this SSH stdout streams back to the CI console.
capture_diagnostics() {
  echo "===== DIAGNOSTICS: $service ====="
  sudo systemctl status "$service" --no-pager -l 2>&1 | head -n 20 || true
  echo "----- journalctl -u $service (last 200 lines) -----"
  sudo journalctl -u "$service" --no-pager -n 200 2>&1 || true
  if [[ "$app" == "cribl" ]]; then
    echo "----- /opt/cribl/log/cribl.log (last 100 lines) -----"
    sudo tail -n 100 /opt/cribl/log/cribl.log 2>&1 || true
    echo "----- cribl worker logs (last 100 lines) -----"
    sudo tail -n 100 /opt/cribl/log/worker/*/cribl.log 2>&1 || true
  fi
  echo "===== END DIAGNOSTICS ====="
}

# Start service
echo "Starting $service..."
if ! sudo systemctl start "$service"; then
  echo "Failed to start $service"
  exit 1
fi

# Wait for the service to be STABLY ready before generating load.
#
# Cribl edge bounces once during early startup (~20s after start): it logs
# "stale pid file" -> systemd "Scheduled restart". A plain "port is listening"
# check passes during the first up-window, so load would start and then the
# bounce kills it mid-run (connection reset -> refused). A transient-inactive
# check also mis-fires, reading the bounce as a crash.
#
# So require the service to be active AND the port listening *continuously* for
# STABILITY_SECS. Any blip (the bounce) resets the counter, so we only proceed
# once startup has truly settled. Harmless for agents that come up clean — they
# just satisfy the window immediately.
STABILITY_SECS=30
OVERALL_TIMEOUT=300
echo "Waiting for $service to be stably ready (port $port up + active for ${STABILITY_SECS}s, timeout ${OVERALL_TIMEOUT}s)..."
port_ready=false
stable=0
for ((i=0; i<OVERALL_TIMEOUT; i++)); do
  if sudo systemctl is-active --quiet "$service" && nc -z localhost "$port" 2>/dev/null; then
    stable=$((stable + 1))
    if (( stable >= STABILITY_SECS )); then
      echo "$service stably ready (port $port up + active for ${STABILITY_SECS}s, after ${i}s)"
      port_ready=true
      break
    fi
  else
    if (( stable > 0 )); then
      echo "Service/port not ready at ${i}s — resetting stability counter (service likely restarting)"
    fi
    stable=0
  fi
  sleep 1
done

if [[ "$port_ready" != true ]]; then
  echo "$service did not reach a stable ready state within ${OVERALL_TIMEOUT}s"
  capture_diagnostics
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
      --endpoint "$endpoint" \
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
  elif [[ "$app" == "otelcol" ]]; then
    loadgen \
      --endpoint "$endpoint" \
      --format nginx_log \
      --number 1 \
      --workers "$i" \
      --period 1ms \
      --total-time 1m \
      --monitor-self \
      --monitor-process "otelcol-contrib"
  elif [[ "$app" == "fluentd" ]]; then
    # fluentd runs as ruby under a supervisor; monitor the worker process by PID.
    fd_pid=$(pgrep -f 'under-supervisor' | head -1)
    [[ -z "$fd_pid" ]] && fd_pid=$(pgrep -f '[f]luentd' | tail -1)
    [[ -z "$fd_pid" ]] && echo "Warning: could not find fluentd worker process"
    loadgen \
      --endpoint "$endpoint" \
      --format nginx_log \
      --number 1 \
      --workers "$i" \
      --period 1ms \
      --total-time 1m \
      --monitor-self \
      --monitor-pid "${fd_pid}"
  else
    loadgen \
      --endpoint "$endpoint" \
      --format nginx_log \
      --number 1 \
      --workers "$i" \
      --period 1ms \
      --total-time 1m \
      --monitor-self \
      --monitor-process "${app}"
  fi

  echo "Finished loadgen with ${i} workers for $app"

  # loadgen exits 0 even when every send fails (it only logs the errors), so a
  # mid-run agent crash would otherwise be reported as a successful run with
  # garbage data. Assert the agent is still alive and fail loudly if not.
  if ! sudo systemctl is-active --quiet "$service"; then
    echo "ERROR: $service is not active after the ${i}-worker run — agent died mid-benchmark"
    capture_diagnostics
    exit 1
  fi

  # Wait for 60 seconds before starting next iteration
  sleep 60
done
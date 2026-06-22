#!/usr/bin/env bash

set -e

git_root=$(git rev-parse --show-toplevel)
# shellcheck source=./functions.sh
source "functions.sh" || exit 1

ed_benchmark=0
cribl_benchmark=0

# All pipeline cases and vendors the suite knows about, in canonical run order.
ALL_CASES=("pass-through" "filter" "mask" "lookup")
ALL_VENDORS=("edgedelta" "cribl" "otelcol" "fluentd")

# Selections default to everything (preserves the previous "run all" behaviour).
SELECTED_CASES=("${ALL_CASES[@]}")
SELECTED_VENDORS=("${ALL_VENDORS[@]}")

usage() {
  cat <<EOF
Usage: ./run.sh [--cases <list>] [--vendors <list>]

Run the pipeline benchmark suite. With no flags, every case runs for every
vendor (the previous default behaviour).

Options:
  --cases <list>     Comma- or space-separated pipeline cases to run.
                     Valid: ${ALL_CASES[*]}
                     Example: --cases pass-through,mask
  --vendors <list>   Comma- or space-separated vendors to run.
                     Valid: ${ALL_VENDORS[*]}
                     Example: --vendors edgedelta,cribl
  -h, --help         Show this help and exit.

Notes:
  * "passthrough" is accepted as an alias for "pass-through".
  * otelcol has no lookup case; it is skipped automatically if requested.
  * Prerequisite checks only run for the selected vendors.
EOF
}

# contains reports whether the first argument equals any of the remaining ones.
contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

is_vendor_selected() {
  contains "$1" "${SELECTED_VENDORS[@]}"
}

# vendor_supported_cases echoes the cases a given vendor can actually run.
vendor_supported_cases() {
  case "$1" in
    otelcol) echo "pass-through filter mask" ;;
    *)       echo "pass-through filter mask lookup" ;;
  esac
}

# cases_for echoes the selected cases that the given vendor supports, in
# canonical order. Empty output means "nothing to run for this vendor".
cases_for() {
  local vendor="$1"
  local supported
  supported=$(vendor_supported_cases "$vendor")
  local c out=()
  for c in "${ALL_CASES[@]}"; do
    if contains "$c" "${SELECTED_CASES[@]}" && contains "$c" $supported; then
      out+=("$c")
    fi
  done
  echo "${out[*]}"
}

# maybe_run executes the benchmark function only if its vendor is selected and
# at least one selected case applies to it.
maybe_run() {
  local vendor="$1" fn="$2"
  if ! is_vendor_selected "$vendor"; then
    echo "Skipping $vendor benchmark (vendor not selected)"
    return 0
  fi
  if [[ -z "$(cases_for "$vendor")" ]]; then
    echo "Skipping $vendor benchmark (no selected case applies; selected: ${SELECTED_CASES[*]})"
    return 0
  fi
  "$fn"
}

# parse_selection validates a comma/space-separated list against the allowed
# values for the given kind, normalises aliases, and writes the deduplicated
# result into the PARSED_SELECTION global array. It exits on invalid input.
PARSED_SELECTION=()
parse_selection() {
  local kind="$1" raw_list="$2"
  local -a allowed=()
  if [[ "$kind" == "cases" ]]; then
    allowed=("${ALL_CASES[@]}")
  else
    allowed=("${ALL_VENDORS[@]}")
  fi
  PARSED_SELECTION=()
  local raw v
  for raw in ${raw_list//,/ }; do
    v="$raw"
    [[ "$kind" == "cases" && "$v" == "passthrough" ]] && v="pass-through"
    if ! contains "$v" "${allowed[@]}"; then
      echo "Invalid $kind: '$raw' (valid: ${allowed[*]})" >&2
      exit 1
    fi
    contains "$v" "${PARSED_SELECTION[@]}" || PARSED_SELECTION+=("$v")
  done
  if [[ ${#PARSED_SELECTION[@]} -eq 0 ]]; then
    echo "No valid $kind selected" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cases)
      [[ -n "${2:-}" ]] || { echo "--cases requires a value" >&2; usage; exit 1; }
      parse_selection cases "$2"; SELECTED_CASES=("${PARSED_SELECTION[@]}"); shift 2 ;;
    --cases=*)
      parse_selection cases "${1#*=}"; SELECTED_CASES=("${PARSED_SELECTION[@]}"); shift ;;
    --vendors)
      [[ -n "${2:-}" ]] || { echo "--vendors requires a value" >&2; usage; exit 1; }
      parse_selection vendors "$2"; SELECTED_VENDORS=("${PARSED_SELECTION[@]}"); shift 2 ;;
    --vendors=*)
      parse_selection vendors "${1#*=}"; SELECTED_VENDORS=("${PARSED_SELECTION[@]}"); shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

echo "Selected vendors: ${SELECTED_VENDORS[*]}"
echo "Selected cases:   ${SELECTED_CASES[*]}"

function check_prerequisites() {
  if is_vendor_selected "edgedelta"; then
    # Edge Delta variables
    check_vars "ED_ORG_ID" "ED_API_TOKEN"
  fi

  if is_vendor_selected "cribl"; then
    # Cribl variables
    check_vars "CRIBL_WORKSPACE" "CRIBL_ORG" "CRIBL_WORKER_GROUP" "CRIBL_CLIENT_ID" "CRIBL_CLIENT_SECRET" "CRIBL_LEADER_TOKEN"
  fi

}

function create_benchmark_environment() {
  echo "Creating benchmark resources..."
  create_benchmark_resources
  echo "Benchmark resources created successfully"
}

function prepare_for_benchmark() {
  update_s3_placeholder
  upload_folder_to_ec2_instance "$git_root/benchmark_scripts"
  upload_file_to_ec2_instance "$git_root/pipelines/lookup-benchmark.csv" "/tmp/lookup-benchmark.csv"
  run_command_on_ec2_instance "chmod 777 /tmp/lookup-benchmark.csv"
}

function cleanup_benchmark_environment() {
  echo "Destroying benchmark resources..."
  destroy_benchmark_resources
  echo "Benchmark resources destroyed successfully"
  if [[ "$ed_benchmark" -eq 1 ]]; then
    echo "Deleting Edge Delta pipeline..."
    pushd "$git_root/pipelines/edgedelta" > /dev/null
    ./edgedelta-api.sh delete
    popd > /dev/null
    echo "Edge Delta pipeline deleted successfully"
  fi
  if [[ "$cribl_benchmark" -eq 1 ]]; then
    echo "Deleting Cribl resources..."
    pushd "$git_root/pipelines/cribl" > /dev/null
    ./cribl-api.sh cleanup-all
    popd > /dev/null
    echo "Cribl resources deleted successfully"
  fi
}

function run_ed_benchmark() {
  echo "Running Edge Delta benchmark..."
  pushd "$git_root/pipelines/edgedelta" > /dev/null
  ./edgedelta-api.sh create-base
  ed_benchmark=1
  PIPELINE_ID=$(cat pipeline_id.txt)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' -e "s/{ED_API_KEY}/$PIPELINE_ID/g" "$git_root/scripts/install_agent_ed.sh"
  else
    sed -i -e "s/{ED_API_KEY}/$PIPELINE_ID/g" "$git_root/scripts/install_agent_ed.sh"
  fi
  echo "Installing Edge Delta agent..."
  run_scripts_on_ec2_instance "$git_root/scripts/install_agent_ed.sh"
  for type in $(cases_for edgedelta); do
    ./edgedelta-api.sh full $type.yaml
    trigger_benchmark "edgedelta" $type
  done
  popd > /dev/null
}

function run_cribl_benchmark() {
  echo "Running Cribl benchmark..."
  pushd "$git_root/pipelines/cribl" > /dev/null

  ./cribl-api.sh create-http-input
  S3_BUCKET=$(get_s3_bucket_name)
  export CRIBL_S3_BUCKET="$S3_BUCKET"
  ./cribl-api.sh create-s3-destination
  ./cribl-api.sh create-pipeline
  ./cribl-api.sh create-route
  cribl_benchmark=1
  ./cribl-api.sh agent-install > "$git_root/scripts/install_agent_cribl.sh"
  upload_file_to_ec2_instance "$git_root/scripts/install_agent_cribl.sh" /tmp/install_agent_cribl.sh
  run_command_on_ec2_instance "chmod +x /tmp/install_agent_cribl.sh"
  run_command_on_ec2_instance "sudo -E /tmp/install_agent_cribl.sh"
  
  for type in $(cases_for cribl); do
    ./cribl-api.sh update-pipeline $type.json
    trigger_benchmark "cribl" $type
  done
  popd > /dev/null
}

function run_otelcol_benchmark() {
  echo "Running OpenTelemetry Collector benchmark..."
  echo "Installing OpenTelemetry Collector agent..."
  run_scripts_on_ec2_instance "$git_root/scripts/install_agent_otelcol.sh"
  upload_folder_to_ec2_instance "$git_root/pipelines/otelcol"
  # No lookup scenario: OTel contrib has no shipped CSV lookup processor
  # (lookup is excluded automatically by cases_for).
  for type in $(cases_for otelcol); do
    run_command_on_ec2_instance "sudo cp /home/ubuntu/otelcol/$type.yaml /etc/otelcol-contrib/config.yaml"
    trigger_benchmark "otelcol" $type
  done
}

function run_fluentd_benchmark() {
  echo "Running Fluentd benchmark..."
  echo "Installing Fluentd agent..."
  run_scripts_on_ec2_instance "$git_root/scripts/install_agent_fluentd.sh"
  upload_folder_to_ec2_instance "$git_root/pipelines/fluentd"
  for type in $(cases_for fluentd); do
    run_command_on_ec2_instance "sudo cp /home/ubuntu/fluentd/$type.conf /etc/fluent/fluentd.conf"
    trigger_benchmark "fluentd" $type
  done
}


function download_benchmark_results() {
  date_tag=$(date +%Y%m%d_%H%M%S)
  mkdir -p "$git_root/benchmark_results/"
  download_folder_from_ec2_instance "/home/ubuntu/benchmark_scripts/benchmark_results/" "$git_root/benchmark_results/"
  mv "$git_root/benchmark_results/benchmark_results/" "$git_root/benchmark_results/$date_tag/"
  echo "Benchmark results downloaded successfully"
}

function generate_versions_csv() {
  local output_dir="$git_root/benchmark_results/$date_tag"
  local csv_file="$output_dir/versions.csv"

  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi

  echo "Collecting agent versions..."

  local ssh_args=(-o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" "ubuntu@$INSTANCE_IP")

  local ed_version cribl_version otelcol_version fluentd_version
  ed_version=$(ssh "${ssh_args[@]}" "/opt/edgedelta/agent/edgedelta --version 2>/dev/null | cut -d ',' -f 1 | sed 's/Agent version: //' || echo unknown" 2>/dev/null || echo "unknown")
  # `cribl version` (subcommand) prints the Cribl product version; `cribl --version`
  # falls through to the bundled Node.js runtime (e.g. v22.x). Extract the X.Y.Z product version.
  cribl_version=$(ssh "${ssh_args[@]}" "/opt/cribl/bin/cribl version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown" 2>/dev/null || echo "unknown")
  otelcol_version=$(ssh "${ssh_args[@]}" "otelcol-contrib --version 2>/dev/null | awk '{print \$3}' || echo unknown" 2>/dev/null || echo "unknown")
  fluentd_version=$(ssh "${ssh_args[@]}" "/opt/fluent/bin/fluentd --version 2>/dev/null | awk '{print \$2}' || echo unknown" 2>/dev/null || echo "unknown")

  {
    echo "agent,version"
    echo "edgedelta,$ed_version"
    echo "cribl,$cribl_version"
    echo "otelcol,$otelcol_version"
    echo "fluentd,$fluentd_version"
  } > "$csv_file"

  echo "Agent versions saved to $csv_file"
}

check_prerequisites
trap cleanup_benchmark_environment EXIT
create_benchmark_environment
prepare_for_benchmark
maybe_run edgedelta run_ed_benchmark
maybe_run cribl run_cribl_benchmark
maybe_run otelcol run_otelcol_benchmark
maybe_run fluentd run_fluentd_benchmark
download_benchmark_results
generate_versions_csv
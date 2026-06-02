#!/usr/bin/env bash

set -e

git_root=$(git rev-parse --show-toplevel)
# shellcheck source=./functions.sh
source "functions.sh" || exit 1

ed_benchmark=0
bindplane_benchmark=0
cribl_benchmark=0

function check_prerequisites() {
  # Edge Delta variables
  check_vars "ED_ORG_ID" "ED_API_TOKEN" 
  # Cribl variables
  check_vars "CRIBL_WORKSPACE" "CRIBL_ORG" "CRIBL_WORKER_GROUP" "CRIBL_CLIENT_ID" "CRIBL_CLIENT_SECRET" "CRIBL_LEADER_TOKEN"

  if ! command -v bindplane &> /dev/null; then
    echo "Bindplane CLI is not installed"
    install_bindplane_cli
  fi
  # Bindplane API key check
  if ! bindplane profile get | grep -q apiKey; then
    echo "Bindplane CLI is not installed or not configured"
    echo "Please install the Bindplane CLI and configure it with your API key"
    exit 1
  fi
  get_bindplane_installation_command >> "$git_root/scripts/install_agent_bindplane.sh"
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
  if [[ "$bindplane_benchmark" -eq 1 ]]; then
    echo "Deleting Bindplane pipeline..."
    pushd "$git_root/pipelines/bindplane" > /dev/null
    bindplane delete -f "lookup.yaml"
    popd > /dev/null
    echo "Bindplane pipeline deleted successfully"
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
  for type in "pass-through" "filter" "mask" "lookup"; do
    ./edgedelta-api.sh full $type.yaml
    trigger_benchmark "edgedelta" $type
  done
  popd > /dev/null
}

function run_bindplane_benchmark() {
  echo "Running Bindplane benchmark..."
  echo "Creating Bindplane config before agent installation..."
  pushd "$git_root/pipelines/bindplane" > /dev/null
  bindplane apply -f "s3_destination.yaml"
  bindplane_benchmark=1
  echo "Installing Bindplane agent..."
  update_bindplane_aws_credentials >> "$git_root/scripts/update_agent_bindplane.sh"
  upload_file_to_ec2_instance "$git_root/scripts/update_agent_bindplane.sh" /tmp/update_agent_bindplane.sh
  run_command_on_ec2_instance "chmod +x /tmp/update_agent_bindplane.sh"
  run_command_on_ec2_instance "/tmp/update_agent_bindplane.sh"
  for type in "pass-through" "filter" "mask" "lookup"; do
    bindplane apply -f "$type.yaml"
    bindplane rollout start benchmark
    trigger_benchmark "bindplane" $type
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
  
  for type in "pass-through" "filter" "mask" "lookup"; do
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
  # No lookup scenario: OTel contrib has no shipped CSV lookup processor.
  for type in "pass-through" "filter" "mask"; do
    run_command_on_ec2_instance "sudo cp /home/ubuntu/otelcol/$type.yaml /etc/otelcol-contrib/config.yaml"
    trigger_benchmark "otelcol" $type
  done
}


function download_benchmark_results() {
  date_tag=$(date +%Y%m%d_%H%M%S)
  mkdir -p "$git_root/benchmark_results/"
  download_folder_from_ec2_instance "/home/ubuntu/benchmark_scripts/benchmark_results/" "$git_root/benchmark_results/"
  mv "$git_root/benchmark_results/benchmark_results/" "$git_root/benchmark_results/$date_tag/"
  echo "Benchmark results downloaded successfully"
}

check_prerequisites
trap cleanup_benchmark_environment EXIT
create_benchmark_environment
prepare_for_benchmark
run_ed_benchmark
run_bindplane_benchmark
run_cribl_benchmark
run_otelcol_benchmark
download_benchmark_results
#!/usr/bin/env bash

set -e

git_root=$(git rev-parse --show-toplevel)

check_vars(){
  var_names=("$@")
  for var_name in "${var_names[@]}"; do
    if [[ -z "${!var_name}" ]]; then
      echo "$var_name variable is unset."
      var_unset=true
    fi
  done
  if [[ -n "$var_unset" ]]; then
    exit 1
  fi
  return 0
}

install_bindplane_cli() {
  mkdir -p ~/bindplane
  curl -L -o ~/bindplane/bindplane.zip https://storage.googleapis.com/bindplane-op-releases/bindplane/latest/bindplane-ee-linux-amd64.zip
  unzip ~/bindplane/bindplane.zip -d ~/bindplane/
  sudo mv ~/bindplane/bindplane /usr/local/bin/bindplane
  mkdir -p ~/.bindplane/
  bindplane profile set default --api-key "$BINDPLANE_API_KEY" --remote-url https://app.bindplane.com
  bindplane profile use default
}

create_benchmark_resources() {
  pushd "$git_root/aws_resources" > /dev/null
  terraform init && terraform apply -auto-approve
  popd > /dev/null
}

set_instance_ip() {
  pushd "$git_root/aws_resources" > /dev/null
  INSTANCE_IP=$(terraform output -raw public_ip)
  popd > /dev/null
}

destroy_benchmark_resources() {
  pushd "$git_root/aws_resources" > /dev/null
  terraform destroy -auto-approve
  popd > /dev/null
}

run_command_on_ec2_instance() {
  local command="$1"
  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi
  echo "Connecting to EC2 instance at $INSTANCE_IP"
  ssh -t -o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" ubuntu@"$INSTANCE_IP" "$command"
}

run_scripts_on_ec2_instance() {
  local script="$1"
  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi
  echo "Running script $script on EC2 instance at $INSTANCE_IP"
  ssh -t -o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" ubuntu@"$INSTANCE_IP" < "$script"
}

get_s3_bucket_name() {
  pushd "$git_root/aws_resources" > /dev/null
  S3_BUCKET=$(terraform output -raw s3_bucket_name)
  popd > /dev/null
  echo "$S3_BUCKET"
}

update_s3_placeholder() {
  S3_BUCKET=$(get_s3_bucket_name)

  echo "Updating S3 placeholder with $S3_BUCKET"
  pushd "$git_root/pipelines" > /dev/null
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS sed
    find . -name '*.yaml' -exec sed -i '' -e "s/{S3_PLACEHOLDER}/$S3_BUCKET/g" {} \;
  else
    # GNU sed
    find . -name '*.yaml' -exec sed -i -e "s/{S3_PLACEHOLDER}/$S3_BUCKET/g" {} \;
  fi
  popd > /dev/null
}

trigger_benchmark() {
  local agent="$1"
  local type="$2"
  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi
  echo "Triggering benchmark on $INSTANCE_IP"
  ssh -o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" ubuntu@"$INSTANCE_IP" "cd benchmark_scripts && ./trigger_benchmark.sh $agent $type"
}

upload_folder_to_ec2_instance() {
  local folder="$1"
  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi
  echo "Uploading files to $INSTANCE_IP"
  scp -r -o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" "$folder" ubuntu@"$INSTANCE_IP":/home/ubuntu
}

upload_file_to_ec2_instance() {
  local file="$1"
  local destination="$2"
  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi
  echo "Uploading file $file to $destination on $INSTANCE_IP"
  scp -o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" "$file" ubuntu@"$INSTANCE_IP":"$destination"
}

download_folder_from_ec2_instance() {
  local source_folder="$1"
  local destination_folder="$2"
  if [[ -z "$INSTANCE_IP" ]]; then
    set_instance_ip
  fi
  echo "Downloading folder $source_folder from $INSTANCE_IP"
  scp -r -o StrictHostKeyChecking=no -i "$git_root/aws_resources/ec2-benchmark-key.pem" ubuntu@"$INSTANCE_IP":"$source_folder" "$destination_folder"
}

# Bindplane (ObservIQ) agent installation
get_bindplane_installation_command() {
  agent_version="v1.94.2"
  install_command=$(bindplane install agent --platform linux-amd64 --version ${agent_version} --agent-type observiq-otel-collector)
  echo "$install_command -k 'configuration=benchmark'"
  echo "sudo systemctl stop observiq-otel-collector"
}

update_bindplane_aws_credentials() {
  BENCHMARK_AWS_ACCESS_KEY_ID=$(cat "$git_root/aws_resources/benchmark_s3_user_credentials.txt" | jq -r '.id')
  BENCHMARK_AWS_SECRET_ACCESS_KEY=$(cat "$git_root/aws_resources/benchmark_s3_user_credentials.txt" | jq -r '.secret')
  cat << EOF
sudo sed -i "/\[Service\]/a Environment=AWS_ACCESS_KEY_ID=$BENCHMARK_AWS_ACCESS_KEY_ID\nEnvironment=AWS_SECRET_ACCESS_KEY=$BENCHMARK_AWS_SECRET_ACCESS_KEY\nEnvironment=AWS_DEFAULT_REGION=us-west-2" /usr/lib/systemd/system/observiq-otel-collector.service
sudo systemctl daemon-reload
sudo systemctl restart observiq-otel-collector
EOF
}
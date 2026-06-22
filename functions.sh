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
  # .yaml: edgedelta/otelcol; .conf: fluentd. (cribl uses .json via its API.)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS sed
    find . \( -name '*.yaml' -o -name '*.conf' \) -exec sed -i '' -e "s/{S3_PLACEHOLDER}/$S3_BUCKET/g" {} \;
  else
    # GNU sed
    find . \( -name '*.yaml' -o -name '*.conf' \) -exec sed -i -e "s/{S3_PLACEHOLDER}/$S3_BUCKET/g" {} \;
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

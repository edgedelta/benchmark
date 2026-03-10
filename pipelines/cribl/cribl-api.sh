#!/usr/bin/env bash

set -euo pipefail

#
# Cribl Cloud API helper for:
# - HTTP input
# - S3 destination
# - Pipeline
# - Route
# - Deploy & cleanup
#
# Docs:
# - Cribl API overview: https://docs.cribl.io/cribl-as-code/api/
# - Cribl API auth (client credentials -> Bearer token):
#   https://docs.cribl.io/cribl-as-code/api-auth/
# - Examples captured in: pipelines/cribl/doc.md
#

###############################################################################
# Configuration
###############################################################################

: "${CRIBL_WORKSPACE:?Set CRIBL_WORKSPACE (e.g. myws)}"
: "${CRIBL_ORG:?Set CRIBL_ORG (e.g. abc123)}"
: "${CRIBL_WORKER_GROUP:?Set CRIBL_WORKER_GROUP (e.g. default)}"
: "${CRIBL_CLIENT_ID:?Set CRIBL_CLIENT_ID (Cribl API Client ID)}"
: "${CRIBL_CLIENT_SECRET:?Set CRIBL_CLIENT_SECRET (Cribl API Client Secret)}"

CRIBL_BASE_URL="https://${CRIBL_WORKSPACE}-${CRIBL_ORG}.cribl.cloud/api/v1/m/${CRIBL_WORKER_GROUP}"
CRIBL_COMMIT_URL="https://${CRIBL_WORKSPACE}-${CRIBL_ORG}.cribl.cloud/api/v1/version/commit"
CRIBL_DEPLOY_URL="https://${CRIBL_WORKSPACE}-${CRIBL_ORG}.cribl.cloud/api/v1/master/groups/${CRIBL_WORKER_GROUP}/deploy"
#api/v1/master/groups/default_fleet/deploy


# Resource IDs (override via env if needed)
CRIBL_HTTP_INPUT_ID="${CRIBL_HTTP_INPUT_ID:-http_input_benchmark}"
CRIBL_HTTP_INPUT_PORT="${CRIBL_HTTP_INPUT_PORT:-6085}"
CRIBL_S3_OUTPUT_ID="${CRIBL_S3_OUTPUT_ID:-s3_output_benchmark}"
CRIBL_PIPELINE_ID="${CRIBL_PIPELINE_ID:-pipeline_benchmark}"
CRIBL_ROUTE_ID="${CRIBL_ROUTE_ID:-route_benchmark}"

# S3 destination configuration (must be provided separately)
CRIBL_S3_BUCKET="${CRIBL_S3_BUCKET:-http-benchmark-test-bucket}"
CRIBL_S3_REGION="${CRIBL_S3_REGION:-us-west-2}"

# Cached token for this script invocation
CRIBL_TOKEN="${CRIBL_TOKEN:-}"

get_cribl_token() {
  # If caller pre-set CRIBL_TOKEN, honor it and don't re-auth.
  if [[ -n "${CRIBL_TOKEN}" ]]; then
    printf '%s' "${CRIBL_TOKEN}"
    return 0
  fi

  local resp
  resp=$(curl --fail --silent --show-error \
    --request POST \
    --url "https://login.cribl.cloud/oauth/token" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "grant_type": "client_credentials",
  "client_id": "${CRIBL_CLIENT_ID}",
  "client_secret": "${CRIBL_CLIENT_SECRET}",
  "audience": "https://api.cribl.cloud"
}
EOF
  )

  CRIBL_TOKEN=$(printf '%s' "$resp" | jq -r '.access_token')
  if [[ -z "${CRIBL_TOKEN}" || "${CRIBL_TOKEN}" == "null" ]]; then
    echo "Failed to retrieve access_token from Cribl auth response:" >&2
    echo "$resp" >&2
    exit 1
  fi

  printf '%s' "${CRIBL_TOKEN}"
}

auth_header() {
  printf 'Authorization: Bearer %s' "$(get_cribl_token)"
}

###############################################################################
# Agent installation helper
###############################################################################

agent_install_command() {
  command=$(curl "https://${CRIBL_WORKSPACE}-${CRIBL_ORG}.cribl.cloud/init/install-edge.sh?group=${CRIBL_WORKER_GROUP}&token=${CRIBL_LEADER_TOKEN}&user=cribl&user_group=cribl&install_dir=%2Fopt%2Fcribl")

  printf '%s' "$command"
}


###############################################################################
# Create resources
###############################################################################

create_http_input() {
  echo "Creating HTTP input '${CRIBL_HTTP_INPUT_ID}' on port ${CRIBL_HTTP_INPUT_PORT}..."

  curl --fail --silent --show-error \
    --request POST \
    --url "${CRIBL_BASE_URL}/system/inputs" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "id": "${CRIBL_HTTP_INPUT_ID}",
  "type": "http_raw",
  "disabled": false,
  "host": "0.0.0.0",
  "port": ${CRIBL_HTTP_INPUT_PORT}
}
EOF

  echo
}

create_s3_destination() {
  : "${CRIBL_S3_BUCKET:?Set CRIBL_S3_BUCKET to the target bucket name}"

  echo "Creating S3 destination '${CRIBL_S3_OUTPUT_ID}' for bucket ${CRIBL_S3_BUCKET} in region ${CRIBL_S3_REGION}..."

  curl  \
    --request POST \
    --url "${CRIBL_BASE_URL}/system/outputs" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "id": "${CRIBL_S3_OUTPUT_ID}",
  "type": "s3",
  "awsAuthenticationMethod": "auto",
  "region": "${CRIBL_S3_REGION}",
  "bucket": "${CRIBL_S3_BUCKET}",
  "compress": "gzip",
  "compressionLevel": "best_speed",
  "destPath": "cribl",
  "format": "json",
  "stagePath": "\$CRIBL_HOME/state/outputs/staging",
  "emptyDirCleanupSec": 300
}
EOF

  echo
}

create_pipeline() {
  echo "Creating pipeline '${CRIBL_PIPELINE_ID}'..."

  # Base pipeline from doc.md: keeps eventSource and eventID, drops all others.
  curl --fail --silent --show-error \
    --request POST \
    --url "${CRIBL_BASE_URL}/pipelines" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "id": "${CRIBL_PIPELINE_ID}",
  "conf": {
    "asyncFuncTimeout": 1000,
    "functions": [
      {
        "filter": "true",
        "conf": {
          "remove": ["*"],
          "keep": ["eventSource", "eventID"]
        },
        "id": "eval",
        "final": true
      }
    ]
  }
}
EOF

  echo
}

create_route() {
  echo "Creating route '${CRIBL_ROUTE_ID}' from '${CRIBL_HTTP_INPUT_ID}' to '${CRIBL_S3_OUTPUT_ID}' via pipeline '${CRIBL_PIPELINE_ID}'..."
  echo "Saving original route configuration to cribl-route-original.json"
  curl --fail --silent --show-error \
    --request GET \
    --url "${CRIBL_BASE_URL}/routes/default" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    | jq '.items[]' | tee cribl-route-original.json
  echo "Original route configuration saved to cribl-route-original.json"

  echo "Updating route configuration"
  curl  \
    --request PATCH \
    --url "${CRIBL_BASE_URL}/routes/default" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "id": "default",
  "groups": {},
  "comments": [],
  "routes": [
    {
      "id": "${CRIBL_ROUTE_ID}",
      "name": "http-benchmark-route",
      "description": "http-benchmark-route",
      "filter": "__inputId=='http_raw:${CRIBL_HTTP_INPUT_ID}'",
      "final": true,
      "disabled": false,
      "enableOutputExpression": false,
      "clones": [],
      "pipeline": "${CRIBL_PIPELINE_ID}",
      "output": "${CRIBL_S3_OUTPUT_ID}"
    }
  ]
}
EOF

  echo
}

commit_config() {
  local commit_response commit_id
  commit_response=$(curl --fail --silent --show-error \
    --request POST \
    --url "${CRIBL_COMMIT_URL}" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "message": "Committing pipeline and route updates",
  "group": "${CRIBL_WORKER_GROUP}"
}
EOF
  )

  # Response shape (see test.json):
  # {
  #   "items": [
  #     {
  #       "branch": "master",
  #       "commit": "<hash>",
  #       ...
  #     }
  #   ],
  #   "count": 1
  # }
  commit_id=$(printf '%s' "$commit_response" | jq -r '.items[0].commit')
  if [[ -z "$commit_id" || "$commit_id" == "null" ]]; then
    echo "Failed to get commit hash from commit response" >&2
    echo "$commit_response" >&2
    exit 1
  fi

  printf '%s\n' "$commit_id"
}

deploy_config() {
  echo "Committing and deploying configuration for worker group '${CRIBL_WORKER_GROUP}'..."

  # First commit, then deploy as per Cribl's commit-and-deploy workflow.
  commit_id=$(commit_config)
  echo "Commit ID: $commit_id"
  curl --fail --silent --show-error \
    --request PATCH \
    --url "${CRIBL_DEPLOY_URL}" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @- <<EOF
{
  "version": "${commit_id}"
}
EOF

  echo
}

###############################################################################
# Pipeline update helper
###############################################################################

# Update pipeline using a full JSON definition from a file.
# NOTE: Cribl PATCH semantics require a full resource representation.
# Usage: update_pipeline_from_file path/to/pipeline.json
update_pipeline_from_file() {
  local file="${1:?Usage: update_pipeline_from_file PATH_TO_JSON}"
  if [[ ! -f "$file" ]]; then
    echo "Pipeline config file not found: $file" >&2
    exit 1
  fi

  echo "Updating pipeline '${CRIBL_PIPELINE_ID}' from ${file}..."

  curl --fail --silent --show-error \
    --request PATCH \
    --url "${CRIBL_BASE_URL}/pipelines/${CRIBL_PIPELINE_ID}" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @"${file}"
  echo "Deploying configuration..."
  deploy_config
  echo "Pipeline updated and deployed successfully" 
}

###############################################################################
# Delete / cleanup
###############################################################################

delete_route() {
  echo "Reverting route '${CRIBL_ROUTE_ID}' to original configuration..."
  curl --silent --show-error \
    --request PATCH \
    --url "${CRIBL_BASE_URL}/routes/default" \
    --header "$(auth_header)" \
    --header "Content-Type: application/json" \
    --data @cribl-route-original.json
  echo "Route reverted to original configuration"
}

delete_http_input() {
  echo "Deleting HTTP input '${CRIBL_HTTP_INPUT_ID}' (if it exists)..."
  curl --silent --show-error \
    --request DELETE \
    --url "${CRIBL_BASE_URL}/system/inputs/${CRIBL_HTTP_INPUT_ID}" \
    --header "$(auth_header)" || true
  echo
}

delete_s3_destination() {
  echo "Deleting S3 destination '${CRIBL_S3_OUTPUT_ID}' (if it exists)..."
  curl --silent --show-error \
    --request DELETE \
    --url "${CRIBL_BASE_URL}/system/outputs/${CRIBL_S3_OUTPUT_ID}" \
    --header "$(auth_header)" || true
  echo
}

delete_pipeline() {
  echo "Deleting pipeline '${CRIBL_PIPELINE_ID}' (if it exists)..."
  curl --silent --show-error \
    --request DELETE \
    --url "${CRIBL_BASE_URL}/pipelines/${CRIBL_PIPELINE_ID}" \
    --header "$(auth_header)" || true
  echo
}

cleanup_all() {
  echo "Cleaning up route, input, destination, and pipeline..."
  delete_route
  delete_http_input
  delete_s3_destination
  delete_pipeline
  deploy_config
}

###############################################################################
# CLI wrapper
###############################################################################

usage() {
  cat <<EOF
Usage: $0 COMMAND [args...]

Commands:
  create-http-input        Create the HTTP input
  create-s3-destination    Create the S3 destination
  create-pipeline          Create the pipeline
  create-route             Create the route
  deploy                   Deploy current configuration
  create-all               Create input, destination, pipeline, route, then deploy

  update-pipeline FILE     PATCH pipeline using full JSON from FILE

  delete-route             Delete the route
  delete-http-input        Delete the HTTP input
  delete-s3-destination    Delete the S3 destination
  delete-pipeline          Delete the pipeline
  cleanup-all              Delete route, input, destination, pipeline, then deploy
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    agent-install)         agent_install_command ;;
    create-http-input)     create_http_input ;;
    create-s3-destination) create_s3_destination ;;
    create-pipeline)       create_pipeline ;;
    create-route)          create_route ;;
    deploy)                deploy_config ;;
    create-all)
      create_http_input
      create_s3_destination
      create_pipeline
      create_route
      deploy_config
      ;;

    update-pipeline)       update_pipeline_from_file "$@" ;;

    delete-route)          delete_route ;;
    delete-http-input)     delete_http_input ;;
    delete-s3-destination) delete_s3_destination ;;
    delete-pipeline)       delete_pipeline ;;
    cleanup-all)           cleanup_all ;;

    ""|help|-h|--help)     usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi


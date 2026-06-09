#!/usr/bin/env bash

set -e

otelcol_version=$(curl -sSL "https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases/latest" \
  | jq -r '.tag_name | ltrimstr("v")')

curl -sSL -o otelcol-contrib.deb \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${otelcol_version}/otelcol-contrib_${otelcol_version}_linux_amd64.deb"
sudo dpkg -i otelcol-contrib.deb
rm otelcol-contrib.deb

sudo systemctl stop otelcol-contrib || true

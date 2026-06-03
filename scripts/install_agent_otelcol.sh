#!/usr/bin/env bash

set -e

otelcol_version="0.153.0"

curl -sSL -o otelcol-contrib.deb \
  "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${otelcol_version}/otelcol-contrib_${otelcol_version}_linux_amd64.deb"
sudo dpkg -i otelcol-contrib.deb
rm otelcol-contrib.deb

sudo systemctl stop otelcol-contrib || true

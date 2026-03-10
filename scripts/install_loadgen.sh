#!/usr/bin/env bash

set -e


loadgen_version="1.1.0"
# Install Go
curl -sSL https://github.com/edgedelta/loadgen/releases/download/v${loadgen_version}/loadgen_${loadgen_version}_Linux_x86_64.tar.gz --output loadgen.tar.gz
sudo tar -xf loadgen.tar.gz -C /usr/local/bin/
rm loadgen.tar.gz

loadgen --help

# create benchmark scripts directory
mkdir -p ~/benchmark_scripts
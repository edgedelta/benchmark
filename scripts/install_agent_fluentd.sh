#!/usr/bin/env bash

set -e

# Fluentd (fluent-package 5 LTS) for Ubuntu 24.04 "noble".
curl -fsSL https://toolbelt.treasuredata.com/sh/install-ubuntu-noble-fluent-package5-lts.sh | sh

# S3 output plugin is not bundled with fluent-package; install it into the
# bundled Ruby. (record_transformer and grep filters are core.)
sudo /opt/fluent/bin/fluent-gem install fluent-plugin-s3

sudo systemctl stop fluentd || true

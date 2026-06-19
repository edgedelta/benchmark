#!/usr/bin/env bash

set -e

# Logstash from the Elastic 8.x apt repository. The deb bundles its own JDK, the
# s3 output, and the translate/mutate filters — no extra plugin installs needed.
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt-get update
sudo apt-get install -y logstash

sudo systemctl stop logstash || true

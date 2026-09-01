#!/usr/bin/env bash
# Install the red (Rust Edge Delta) agent on the benchmark instance.
# Expects either /tmp/red (prebuilt linux/amd64 binary) or /tmp/red-src.tgz
# (source tarball) to have been uploaded beforehand.

set -e

sudo mkdir -p /opt/red /etc/red

if [[ -f /tmp/red ]]; then
  echo "Installing prebuilt red binary"
  sudo install -m 0755 /tmp/red /opt/red/red
else
  echo "Building red from source"
  if ! command -v cargo >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential pkg-config libssl-dev cmake clang
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  fi
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
  rm -rf "$HOME/red-src" && mkdir -p "$HOME/red-src"
  tar -xzf /tmp/red-src.tgz -C "$HOME/red-src"
  src_dir=$(find "$HOME/red-src" -maxdepth 2 -name Cargo.toml -exec dirname {} \; | head -1)
  (cd "$src_dir" && cargo build --release 2>&1 | tail -n 5)
  sudo install -m 0755 "$src_dir/target/release/red" /opt/red/red
fi

/opt/red/red --version

sudo tee /etc/systemd/system/red.service >/dev/null <<'UNIT'
[Unit]
Description=red - Edge Delta agent (Rust)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/red/red --config /etc/red/config.yaml
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl stop red || true
echo "red installed"

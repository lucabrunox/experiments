#!/bin/bash

set -euxo pipefail

function run_init() {
  echo TODO: this is the real init
}

echo "User data start"

# Give root a HOME, ec2 doesn't set it
export HOME=/root

# Creating swap for low-memory instances, such that e.g. rust installation doesn't fail
dd if=/dev/zero of=/tmp/swapfile bs=1M count=1024
chmod 0600 /tmp/swapfile
mkswap /tmp/swapfile
swapon /tmp/swapfile

# Update system
yum update -y

# Install Rust
yum install -y gcc gcc-c++ make openssl-devel
curl https://sh.rustup.rs -sSf | sh -s -- -y
source $HOME/.cargo/env

# Install outlog
cargo install --git https://github.com/lucabrunox/outlog

# Run init and send output to cw logs
run_init 2>&1 | outlog --aws --aws-log-group-name '/learning/ec2_user_data'

echo "User data end"
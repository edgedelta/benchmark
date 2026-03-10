#!/usr/bin/env bash

set -e

# shellcheck disable=SC1083
ED_API_KEY={ED_API_KEY} \
bash -c "$(curl -L https://release.edgedelta.com/candidate/install.sh)"
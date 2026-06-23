#!/usr/bin/env bash
# run.sh — execute an R script inside the indy-flows container with repo mounted
set -euo pipefail
SCRIPT="${1:?usage: run.sh scripts/NN-name.R}"
podman run --rm \
  --userns=keep-id \
  -v "$(pwd)":/work:z -w /work \
  -e HOME=/work \
  indy-flows:latest \
  Rscript "$SCRIPT"

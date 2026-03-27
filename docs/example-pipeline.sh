#!/usr/bin/env bash
# =============================================================================
# .ci/pipeline.sh — example pipeline script
#
# Drop this file into your repo at .ci/pipeline.sh (chmod +x).
# It is executed by ci-run after every push, with these env vars set:
#
#   CI=true
#   CI_JOB_ID        unique job identifier
#   CI_COMMIT_SHA    full commit hash
#   CI_COMMIT_REF    full ref (e.g. refs/heads/main)
#   CI_REPO          path to the bare repo
#   CI_IMAGES_DIR    path to the OCI image store (/data/images)
# =============================================================================
set -euo pipefail

echo "=== Pipeline: $CI_JOB_ID ==="
echo "Commit : $CI_COMMIT_SHA"
echo "Ref    : $CI_COMMIT_REF"
echo ""

# --- Load a base image from the local OCI store if you need Docker ---
# img-load node:20-alpine

# --- Example: run tests ---
echo "--- Tests ---"
# npm ci
# npm test

# --- Example: build a binary ---
echo "--- Build ---"
# go build -o ./bin/app ./...

# --- Example: build and save a Docker image ---
# docker build -t myapp:$CI_COMMIT_SHA .
# skopeo copy \
#   docker-daemon:myapp:$CI_COMMIT_SHA \
#   oci:/data/images/myapp_${CI_COMMIT_SHA}:latest

echo "Pipeline complete."

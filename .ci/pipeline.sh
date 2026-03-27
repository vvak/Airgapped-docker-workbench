#!/usr/bin/env bash
set -euo pipefail

echo "=== Pipeline running ==="
echo "Job    : $CI_JOB_ID"
echo "Commit : $CI_COMMIT_SHA"
echo "Ref    : $CI_COMMIT_REF"
echo ""

echo "--- Step 1: Check environment ---"
uname -a
echo ""

echo "--- Step 2: List repo contents ---"
ls -la
echo ""

echo "Pipeline complete."

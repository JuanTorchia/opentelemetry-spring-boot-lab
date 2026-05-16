#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
SIZE="small"
RUNS="1"
REQUESTS="12"
WARMUP="3"
CONCURRENCY="2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --requests) REQUESTS="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell 7 (pwsh) is required for the shared runner implementation." >&2
  exit 1
fi

pwsh -NoProfile -ExecutionPolicy Bypass -File "$(dirname "$0")/run-lab.ps1" \
  -Mode "$MODE" \
  -Size "$SIZE" \
  -Runs "$RUNS" \
  -Requests "$REQUESTS" \
  -Warmup "$WARMUP" \
  -Concurrency "$CONCURRENCY"

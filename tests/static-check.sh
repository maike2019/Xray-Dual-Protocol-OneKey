#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/install.sh"
grep -q 'well-known/acme-challenge' "$ROOT/install.sh"
grep -q -- '--install-cronjob' "$ROOT/install.sh"
grep -q 'xtls-rprx-vision' "$ROOT/install.sh"
grep -q 'DEFAULT_REALITY_PORT=8443' "$ROOT/install.sh"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$ROOT/install.sh"
echo "Static checks passed."

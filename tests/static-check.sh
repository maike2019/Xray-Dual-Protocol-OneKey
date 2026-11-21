#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/install.sh"
bash -n "$SCRIPT"
for tag in ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx; do
  grep -q "$tag" "$SCRIPT"
done
grep -q 'grpc_pass unix:' "$SCRIPT"
grep -q 'RuntimeDirectory=xray-dual' "$SCRIPT"
grep -q 'nginx_aggregate' "$SCRIPT"
grep -q '安装全部七种' "$SCRIPT"
grep -q 'well-known/acme-challenge' "$SCRIPT"
grep -q -- '--install-cronjob' "$SCRIPT"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$SCRIPT"
echo "Static checks passed."

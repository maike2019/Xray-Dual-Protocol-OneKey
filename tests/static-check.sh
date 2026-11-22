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
grep -q 'ensure_nginx_http' "$SCRIPT"
grep -q 'assert_port_free_or_nginx 80' "$SCRIPT"
grep -q 'feature/seven-inbound-modes/install.sh' "$ROOT/README.md"
! grep -q 'raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh' "$ROOT/README.md"
! grep -q 'install_ws(){' "$SCRIPT"
! grep -q '80 端口占用，未做任何 kill' "$SCRIPT"
! grep -q 'menu(){' "$SCRIPT"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$SCRIPT"
echo "Static checks passed."

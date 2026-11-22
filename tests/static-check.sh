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
grep -q 'xray_output_field privatekey' "$SCRIPT"
grep -q 'xray_output_field password' "$SCRIPT"
grep -q 'xray_output_field publickey' "$SCRIPT"
grep -q 'REALITY dest 主机名（只填域名/IP，不含端口' "$SCRIPT"
grep -Fq 'dest 端口 [443]' "$SCRIPT"
# Exercise the parser against both documented Xray output formats.
eval "$(sed -n '/^xray_output_field(){/,/^}/p' "$SCRIPT")"
legacy_output=$(printf 'Private key: legacy-private\\nPublic key: legacy-public\\n')
modern_output=$(printf 'PrivateKey: modern-private\\nPassword: modern-password\\nHash32: ignored-hash\\n')
[[ "$(xray_output_field privatekey <<<"$legacy_output")" == "legacy-private" ]]
[[ "$(xray_output_field publickey <<<"$legacy_output")" == "legacy-public" ]]
[[ "$(xray_output_field privatekey <<<"$modern_output")" == "modern-private" ]]
[[ "$(xray_output_field password <<<"$modern_output")" == "modern-password" ]]
grep -q 'feature/seven-inbound-modes/install.sh' "$ROOT/README.md"
! grep -q 'raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh' "$ROOT/README.md"
! grep -q 'install_ws(){' "$SCRIPT"
! grep -q '80 端口占用，未做任何 kill' "$SCRIPT"
! grep -q 'menu(){' "$SCRIPT"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$SCRIPT"
echo "Static checks passed."

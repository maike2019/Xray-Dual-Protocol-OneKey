#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/install.sh"

bash -n "$SCRIPT"
bash -n "$ROOT/lib/management.sh"

for tag in ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx; do
  grep -q "$tag" "$SCRIPT"
done

grep -q 'grpc_pass unix:' "$SCRIPT"
grep -q 'RuntimeDirectory=xray-dual' "$SCRIPT"
grep -q 'nginx_aggregate' "$SCRIPT"
grep -q '安装全部七种' "$SCRIPT"
grep -q 'show_install_status' "$SCRIPT"
grep -q 'install_summary' "$SCRIPT"
grep -q 'INSTALL_TEE_PID' "$SCRIPT"
grep -q 'refresh_saved_links' "$SCRIPT"
grep -q 'make_saved_link' "$SCRIPT"
grep -q 'inbound_health' "$SCRIPT"
grep -q '所有已登记配置及客户端链接' "$SCRIPT"
grep -q '每项验收通过后才进入下一项' "$SCRIPT"
grep -q 'systemctl is-active --quiet xray' "$SCRIPT"
grep -q '客户端链接' "$SCRIPT"
grep -q 'well-known/acme-challenge' "$SCRIPT"
grep -q -- '--install-cronjob' "$SCRIPT"
grep -q 'ensure_nginx_http' "$SCRIPT"
grep -q 'assert_port_free_or_nginx 80' "$SCRIPT"
grep -q 'xray_output_field privatekey' "$SCRIPT"
grep -q 'xray_output_field password' "$SCRIPT"
grep -q 'xray_output_field publickey' "$SCRIPT"
grep -q 'REALITY dest 主机名（只填域名/IP，不含端口' "$SCRIPT"
grep -Fq 'dest 端口 [443]' "$SCRIPT"

# Verify transactional rollback guards are present.
grep -q 'Xray 重启/运行检查失败，已恢复原配置' "$SCRIPT"
grep -q '新 Nginx 配置测试失败，已恢复原项目配置' "$SCRIPT"
grep -q 'Nginx 重载失败，已恢复原项目配置' "$SCRIPT"

# Exercise legacy, intermediate, and current Xray x25519 output labels.
eval "$(sed -n '/^xray_output_field(){/,/^}/p' "$SCRIPT")"
legacy_output=$(printf '%s\n' 'Private key: legacy-private' 'Public key: legacy-public')
intermediate_output=$(printf '%s\n' 'PrivateKey: middle-private' 'Password: middle-password')
current_output=$(printf '%s\n' 'PrivateKey: current-private' 'Password (PublicKey): current-password' 'Hash32: ignored-hash')

[[ "$(xray_output_field privatekey <<<"$legacy_output")" == "legacy-private" ]]
[[ "$(xray_output_field publickey <<<"$legacy_output")" == "legacy-public" ]]
[[ "$(xray_output_field privatekey <<<"$intermediate_output")" == "middle-private" ]]
[[ "$(xray_output_field password <<<"$intermediate_output")" == "middle-password" ]]
[[ "$(xray_output_field privatekey <<<"$current_output")" == "current-private" ]]
[[ "$(xray_output_field password <<<"$current_output")" == "current-password" ]]
[[ "$(xray_output_field publickey <<<"$current_output")" == "current-password" ]]

grep -q '^PROJECT_VERSION=2.1.0-dev
grep -q 'v$PROJECT_VERSION' "$SCRIPT"
! grep -q '^VERSION=' "$SCRIPT"
grep -q 'feature/seven-inbound-modes/install.sh' "$ROOT/README.md"
! grep -q 'raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh' "$ROOT/README.md"
! grep -q 'install_ws(){' "$SCRIPT"
! grep -q '80 端口占用，未做任何 kill' "$SCRIPT"
! grep -q 'menu(){' "$SCRIPT"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$SCRIPT"

echo "Static checks passed."
 "$SCRIPT"
grep -q 'v$PROJECT_VERSION' "$SCRIPT"
! grep -q '^VERSION=' "$SCRIPT"
grep -q 'feature/seven-inbound-modes/install.sh' "$ROOT/README.md"
! grep -q 'raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh' "$ROOT/README.md"
! grep -q 'install_ws(){' "$SCRIPT"
! grep -q '80 端口占用，未做任何 kill' "$SCRIPT"
! grep -q 'menu(){' "$SCRIPT"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$SCRIPT"

echo "Static checks passed."

# Management panel wiring and all requested menu entries.
grep -q 'source "$MANAGEMENT_LIB"' "$SCRIPT"
for entry in '1. 安装单项配置' '2. 按顺序安装全部七种' '3. 查看所有配置' '4. 修改已有配置' '5. 卸载单项配置' '6. 输出客户端链接' '7. 显示二维码' '8. 启动 / 停止 / 重启' '9. 查看运行日志' '10. 配置健康检查' '11. 证书状态与续期检查' '12. 备份配置' '13. 恢复配置'; do
  grep -Fq "$entry" "$ROOT/lib/management.sh"
done
grep -q 'sha256sum -c' "$ROOT/lib/management.sh"
grep -q 'xray run -test -config' "$ROOT/lib/management.sh"
grep -q 'qrencode -t ANSIUTF8' "$ROOT/lib/management.sh"

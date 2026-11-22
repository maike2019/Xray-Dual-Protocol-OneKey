#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/install.sh"
MANAGER="$ROOT/lib/management.sh"

bash -n "$SCRIPT"
bash -n "$MANAGER"

for tag in ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx; do
  grep -q "$tag" "$SCRIPT"
done

for needle in 'grpc_pass unix:' 'RuntimeDirectory=xray-dual' 'nginx_aggregate' '安装全部七种' 'show_install_status' 'install_summary' 'INSTALL_TEE_PID' 'refresh_saved_links' 'make_saved_link' 'inbound_health' 'ensure_nginx_http' 'xray_output_field privatekey' 'xray_output_field password' 'xray_output_field publickey'; do
  grep -Fq "$needle" "$SCRIPT"
done

grep -q '^PROJECT_VERSION=2.1.0-dev$' "$SCRIPT"
grep -q 'source "$MANAGEMENT_LIB"' "$SCRIPT"
grep -q 'Xray 重启/运行检查失败，已恢复原配置' "$SCRIPT"
grep -q '新 Nginx 配置测试失败，已恢复原项目配置' "$SCRIPT"
grep -q 'Nginx 重载失败，已恢复原项目配置' "$SCRIPT"

for entry in '1. 安装单项配置' '2. 按顺序安装全部七种' '3. 查看所有配置' '4. 修改已有配置' '5. 卸载单项配置' '6. 输出客户端链接' '7. 显示二维码' '8. 启动 / 停止 / 重启' '9. 查看运行日志' '10. 配置健康检查' '11. 证书状态与续期检查' '12. 备份配置' '13. 恢复配置'; do
  grep -Fq "$entry" "$MANAGER"
done

grep -q 'sha256sum -c' "$MANAGER"
grep -q 'xray_test' "$MANAGER"
grep -q 'secure_xray_config' "$SCRIPT"
grep -q 'install -o root -g "$service_group" -m 640' "$SCRIPT"
grep -q 'runuser -u "$u" -g "$g" -- xray run -test -config "$CONF"' "$SCRIPT"
grep -q 'qrencode -t ANSIUTF8' "$MANAGER"
grep -q '伪装域名' "$SCRIPT"
grep -q '客户端握手域名' "$SCRIPT"
grep -q 'docs/USER_SUBSCRIPTION_DESIGN.md' "$ROOT/README.md"
grep -q 'feature/seven-inbound-modes/install.sh' "$ROOT/README.md"
! grep -q 'raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh' "$ROOT/README.md"
! grep -Eq 'kill[[:space:]]+-9|killall|pkill' "$SCRIPT"

echo "Static checks passed."

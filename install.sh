#!/usr/bin/env bash
# Derived from wulabing/Xray_onekey; MIT License.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VERSION=1.0.0
XRAY_DIR=/usr/local/etc/xray
CONF=$XRAY_DIR/config.json
NGINX=/etc/nginx/conf.d/xray-dual.conf
WEBROOT=/var/www/xray-acme
CERTDIR=/ssl
CERT=$CERTDIR/xray.crt
KEY=$CERTDIR/xray.key
STATE=/etc/xray-dual-protocol
HOOK=/usr/local/sbin/xray-dual-cert-reload
DEFAULT_REALITY_PORT=8443
ok(){ echo "[OK] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "请以 root 运行"
command -v jq >/dev/null || die "缺少 jq"
backup(){ [[ -e "$1" ]] && cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"; }
valid_port(){ [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1>=1 && 10#$1<=65535)); }
port_free(){
  if ss -H -lntup "( sport = :$1 )" 2>/dev/null | grep -q .; then
    ss -lntup "( sport = :$1 )" || true
    return 1
  fi
  return 0
}
xray_test(){ xray run -test -config "$CONF"; }
apply_config(){
  local t b
  t=$(mktemp "$XRAY_DIR/config.XXXXXX")
  cat >"$t"; jq empty "$t" || { rm -f "$t"; die "JSON 无效"; }
  backup "$CONF"; install -m 600 "$t" "$CONF"; rm -f "$t"
  if ! xray_test; then
    b=$(ls -1t "$CONF".bak.* 2>/dev/null | head -1 || true)
    [[ -n "$b" ]] && cp -a "$b" "$CONF"
    die "Xray 测试失败，已尝试回滚"
  fi
  systemctl restart xray
}
install_deps(){
  . /etc/os-release
  [[ "$ID" == debian || "$ID" == ubuntu ]] || die "首版仅支持 Debian/Ubuntu"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates jq nginx cron openssl
  systemctl enable --now nginx
  systemctl enable --now cron 2>/dev/null || true
  mkdir -p "$XRAY_DIR" "$(dirname "$NGINX")" "$WEBROOT" "$CERTDIR" "$STATE"
}
install_xray(){
  if ! command -v xray >/dev/null 2>&1; then
    curl -fsSL --retry 3 https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o /tmp/xray-install.sh
    bash /tmp/xray-install.sh install
    rm -f /tmp/xray-install.sh
  fi
  systemctl enable xray
}
write_hook(){
cat >"$HOOK" <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
u=$(systemctl show xray -p User --value 2>/dev/null || true)
[[ -n "$u" ]] || u=nobody
id "$u" >/dev/null 2>&1 || u=nobody
g=$(id -gn "$u")
chown "$u:$g" /ssl /ssl/xray.crt /ssl/xray.key
chmod 750 /ssl
chmod 640 /ssl/xray.crt /ssl/xray.key
nginx -t
xray run -test -config /usr/local/etc/xray/config.json
systemctl reload nginx
systemctl restart xray
HOOK
chmod 750 "$HOOK"
}
nginx_conf(){
 local d="$1" p="$2" path="$3"
 cat >"$NGINX" <<EOF
server {
 listen 80;
 listen [::]:80;
 server_name $d;
 root $WEBROOT;
 location ^~ /.well-known/acme-challenge/ {
   default_type "text/plain";
   try_files \$uri =404;
 }
 location / { return 301 https://\$host\$request_uri; }
}
server {
 listen 443 ssl;
 listen [::]:443 ssl;
 http2 on;
 server_name $d;
 ssl_certificate $CERT;
 ssl_certificate_key $KEY;
 ssl_protocols TLSv1.2 TLSv1.3;
 location $path {
   proxy_pass http://127.0.0.1:$p;
   proxy_http_version 1.1;
   proxy_set_header Upgrade \$http_upgrade;
   proxy_set_header Connection "upgrade";
   proxy_set_header Host \$host;
   proxy_set_header X-Real-IP \$remote_addr;
 }
 location / { return 404; }
}
EOF
 nginx -t
}
acme_setup(){
 command -v curl >/dev/null
 [[ -x "$HOME/.acme.sh/acme.sh" ]] || curl -fsSL https://get.acme.sh | sh -s "email=admin@$DOMAIN"
 "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt
 "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade
 write_hook
 "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --webroot "$WEBROOT" --keylength ec-256
 mkdir -p "$CERTDIR"
 "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" --ecc --key-file "$KEY" --fullchain-file "$CERT" --reloadcmd "$HOOK"
 "$HOME/.acme.sh/acme.sh" --install-cronjob || true
 "$HOOK"
}
new_uuid(){ cat /proc/sys/kernel/random/uuid; }
reality_keys(){
 local o
 o=$(xray x25519 2>&1) || die "xray x25519 失败：$o"
 R_PRIV=$(awk -F ': *' '/PrivateKey:/ {print $2;exit}' <<<"$o")
 R_PUB=$(awk -F ': *' '/Password:/ {print $2;exit}' <<<"$o")
 [[ -n "$R_PRIV" && -n "$R_PUB" ]] || die "无法识别 xray x25519 输出，停止以避免写入空密钥"
}
install_ws(){
 read -rp "WS TLS 域名（A/AAAA 应指向本机）: " d
 [[ "$d" =~ ^[A-Za-z0-9.-]+$ ]] || die "域名格式不正确"
 DOMAIN=$d
 port_free 80 || die "80 端口占用，未做任何 kill"
 port_free 443 || die "443 端口占用，未做任何 kill"
 local p path id base
 p=$(shuf -i 12000-50000 -n 1); port_free "$p" || die "回源端口占用，请重试"
 path="/$(openssl rand -hex 8)/"; id=$(new_uuid)
 # 先放置只含 challenge 的 HTTP 配置，签发不依赖 TLS 端口
 cat >"$NGINX" <<EOF
server {
 listen 80;
 listen [::]:80;
 server_name $DOMAIN;
 root $WEBROOT;
 location ^~ /.well-known/acme-challenge/ { default_type "text/plain"; try_files \$uri =404; }
 location / { return 404; }
}
EOF
 nginx -t && systemctl reload nginx
 acme_setup
 nginx_conf "$DOMAIN" "$p" "$path"
 base=$(cat "$CONF" 2>/dev/null || echo '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}')
 jq --arg id "$id" --argjson p "$p" --arg path "$path" '
 .inbounds=((.inbounds//[])|map(select(.tag!="dual-ws")))+[{"tag":"dual-ws","listen":"127.0.0.1","port":$p,"protocol":"vless","settings":{"clients":[{"id":$id}],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":$path}}}]
 ' <<<"$base" | apply_config
 printf 'WS_DOMAIN=%s\nWS_UUID=%s\nWS_PORT=%s\nWS_PATH=%s\n' "$DOMAIN" "$id" "$p" "$path" >>"$STATE/installed"
 systemctl reload nginx
 echo "WS 分享链接：vless://$id@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$(jq -rn --arg x "$path" '$x|@uri')#WS-TLS"
}
install_reality(){
 local p dest dp sni sid id base ip
 read -rp "REALITY 监听端口 [8443]: " p; p=${p:-$DEFAULT_REALITY_PORT}
 valid_port "$p" || die "监听端口无效"; port_free "$p" || die "端口占用，未杀进程"
 read -rp "dest 目标域名: " dest; [[ "$dest" =~ ^[A-Za-z0-9.-]+$ ]] || die "域名格式无效"
 read -rp "dest 端口 [443]: " dp; dp=${dp:-443}; valid_port "$dp" || die "dest 端口无效"
 read -rp "serverName/SNI [$dest]: " sni; sni=${sni:-$dest}
 [[ "$sni" =~ ^[A-Za-z0-9.-]+$ ]] || die "SNI 格式无效"
 id=$(new_uuid); sid=$(openssl rand -hex 8); reality_keys
 base=$(cat "$CONF" 2>/dev/null || echo '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"}]}')
 jq --arg id "$id" --argjson p "$p" --arg dest "$dest:$dp" --arg sni "$sni" --arg sid "$sid" --arg pk "$R_PRIV" '
 .inbounds=((.inbounds//[])|map(select(.tag!="dual-reality")))+[{"tag":"dual-reality","listen":"0.0.0.0","port":$p,"protocol":"vless","settings":{"clients":[{"id":$id,"flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":$dest,"xver":0,"serverNames":[$sni],"privateKey":$pk,"shortIds":[$sid]}}}]
 ' <<<"$base" | apply_config
 ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
 printf 'REALITY_UUID=%s\nREALITY_PORT=%s\nREALITY_DEST=%s:%s\nREALITY_SNI=%s\nREALITY_SID=%s\nREALITY_PUBLIC=%s\n' "$id" "$p" "$dest" "$dp" "$sni" "$sid" "$R_PUB" >>"$STATE/installed"
 echo "REALITY 分享链接：vless://$id@$ip:$p?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$R_PUB&sid=$sid&type=tcp#REALITY-Vision"
 echo "请在系统防火墙和云安全组放行 TCP/$p"
}
show_info(){
 [[ -f "$CONF" ]] || { echo "尚无配置"; return; }
 jq -r '.inbounds[]|[.tag,.listen,.port,.protocol,(.streamSettings.security//"none")]|@tsv' "$CONF"
 [[ -f "$STATE/installed" ]] && cat "$STATE/installed"
}
manage_reality(){
 [[ -f "$CONF" ]] || die "Xray 配置不存在"
 jq -e '.inbounds[]|select(.tag=="dual-reality")' "$CONF" >/dev/null || die "REALITY 尚未安装"
 echo "1) 修改端口 2) 修改 dest/SNI 3) 重新生成密钥与 Short ID"
 read -rp "选择: " c
 local t
 t=$(mktemp)
 case "$c" in
 1) read -rp "新端口: " p; valid_port "$p" || die "端口无效"; port_free "$p" || die "端口占用"; jq --argjson p "$p" '(.inbounds[]|select(.tag=="dual-reality").port)=$p' "$CONF" >"$t" ;;
 2) read -rp "dest 域名: " d; [[ "$d" =~ ^[A-Za-z0-9.-]+$ ]] || die "域名无效"; read -rp "dest 端口 [443]: " dp; dp=${dp:-443}; valid_port "$dp" || die "端口无效"; read -rp "SNI [$d]: " s; s=${s:-$d}; jq --arg d "$d:$dp" --arg s "$s" '(.inbounds[]|select(.tag=="dual-reality").streamSettings.realitySettings.dest)=$d | (.inbounds[]|select(.tag=="dual-reality").streamSettings.realitySettings.serverNames)=[$s]' "$CONF" >"$t" ;;
 3) reality_keys; sid=$(openssl rand -hex 8); jq --arg k "$R_PRIV" --arg s "$sid" '(.inbounds[]|select(.tag=="dual-reality").streamSettings.realitySettings.privateKey)=$k | (.inbounds[]|select(.tag=="dual-reality").streamSettings.realitySettings.shortIds)=[$s]' "$CONF" >"$t"; echo "新客户端参数 PublicKey=$R_PUB ShortID=$sid" ;;
 *) rm -f "$t"; die "无效选项" ;;
 esac
 cat "$t" | apply_config; rm -f "$t"
}
menu(){
 echo "Xray Dual Protocol OneKey v$VERSION"
 echo "1) 安装/补装 WS  2) 安装/补装 REALITY  3) 安装两者  4) 查看配置  5) 管理 REALITY  6) 证书状态  0) 退出"
 read -rp "选择: " n
 case "$n" in
 1|2|3) install_deps; install_xray; [[ "$n" == 1 || "$n" == 3 ]] && install_ws; [[ "$n" == 2 || "$n" == 3 ]] && install_reality ;;
 4) show_info ;;
 5) manage_reality ;;
 6) "$HOME/.acme.sh/acme.sh" --list 2>/dev/null || true; systemctl list-timers --all 2>/dev/null|grep -i acme || true; crontab -l 2>/dev/null|grep -i acme || true; openssl x509 -in "$CERT" -noout -dates 2>/dev/null || true ;;
 0) exit 0 ;;
 *) die "无效选项" ;;
 esac
}
menu

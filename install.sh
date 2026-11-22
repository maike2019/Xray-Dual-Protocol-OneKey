#!/usr/bin/env bash
# Derived from wulabing/Xray_onekey; MIT License.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PROJECT_VERSION=2.1.0-dev
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
backup(){ [[ -e "$1" ]] && cp -a "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"; }
valid_port(){ [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1>=1 && 10#$1<=65535)); }
xray_test(){ xray run -test -config "$CONF"; }
apply_config(){
  local t b stamp
  t=$(mktemp "$XRAY_DIR/config.XXXXXX")
  cat >"$t"
  if ! jq empty "$t" >/dev/null 2>&1; then
    rm -f "$t"
    echo "[ERROR] 新生成的 Xray JSON 无效，原配置未修改" >&2
    return 1
  fi
  stamp=$(date +%Y%m%d%H%M%S)
  b="$CONF.bak.$stamp"
  cp -a "$CONF" "$b"
  install -m 600 "$t" "$CONF"
  rm -f "$t"
  if ! xray_test; then
    cp -a "$b" "$CONF"
    xray_test >/dev/null 2>&1 || true
    echo "[ERROR] Xray 配置测试失败，已恢复原配置（备份：$b）" >&2
    return 1
  fi
  if ! systemctl restart xray || ! systemctl is-active --quiet xray; then
    cp -a "$b" "$CONF"
    xray_test >/dev/null 2>&1 || true
    systemctl restart xray >/dev/null 2>&1 || true
    echo "[ERROR] Xray 重启/运行检查失败，已恢复原配置并尝试恢复旧服务（备份：$b）" >&2
    return 1
  fi
}
install_deps(){
  . /etc/os-release
  [[ "$ID" == debian || "$ID" == ubuntu ]] || die "首版仅支持 Debian/Ubuntu"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates jq nginx cron openssl iproute2 qrencode
  systemctl enable --now cron 2>/dev/null || true
  mkdir -p "$XRAY_DIR" "$(dirname "$NGINX")" "$WEBROOT" "$CERTDIR" "$STATE"
  command -v jq >/dev/null 2>&1 || die "jq 安装失败；请检查 apt 源和网络后重试"
}
port_listener_lines(){
  ss -H -lntp "( sport = :$1 )" 2>/dev/null || true
}
listener_processes(){
  local lines
  lines=$(port_listener_lines "$1")
  [[ -n "$lines" ]] || return 0
  sed -n 's/.*users:(\(.*\)).*/\1/p' <<<"$lines" |
    grep -oE '"[^"]+"' | tr -d '"' | sort -u
}
assert_port_free_or_nginx(){
  local port="$1" lines processes
  lines=$(port_listener_lines "$port")
  [[ -n "$lines" ]] || return 0
  processes=$(listener_processes "$port")
  if [[ "$processes" != "nginx" ]]; then
    printf '%s\n' "$lines" >&2
    return 1
  fi
}
ensure_nginx_http(){
  local lines processes
  if ! assert_port_free_or_nginx 80; then
    die "TCP/80 已被非 Nginx 服务占用；请先确认占用程序，脚本不会结束任何进程"
  fi
  systemctl enable nginx
  systemctl start nginx || {
    systemctl status nginx --no-pager >&2 || true
    die "Nginx 启动失败，请检查 systemctl status nginx 和 journalctl -u nginx"
  }
  lines=$(port_listener_lines 80)
  processes=$(listener_processes 80)
  [[ -n "$lines" && "$processes" == "nginx" ]] ||
    die "Nginx 启动后未能独占监听 TCP/80，停止签发证书"
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
# Extract Xray CLI fields across both legacy and current x25519 output labels.
# Examples supported: "Private key:" / "Public key:" and "PrivateKey:" / "Password:".
xray_output_field(){
 local wanted="$1"
 awk -F: -v wanted="$wanted" '
   NF >= 2 {
     label=tolower($1)
     # Remove spaces and punctuation so "Password (PublicKey)" becomes
     # "passwordpublickey", while accepting the older label variants.
     gsub(/[^[:alnum:]]/, "", label)
     if (label == wanted ||
         (wanted == "password" && label == "passwordpublickey") ||
         (wanted == "publickey" && label == "passwordpublickey")) {
       value=substr($0, index($0, ":")+1)
       sub(/^[[:space:]]+/, "", value)
       sub(/[[:space:]\r]+$/, "", value)
       print value
       exit
     }
   }'
}
reality_keys(){
 local o xver
 o=$(xray x25519 2>&1) || die "xray x25519 命令执行失败；请先运行 xray version 检查 Xray 安装"
 R_PRIV=$(xray_output_field privatekey <<<"$o")
 R_PUB=$(xray_output_field password <<<"$o")
 [[ -n "$R_PUB" ]] || R_PUB=$(xray_output_field publickey <<<"$o")
 if [[ -z "$R_PRIV" || -z "$R_PUB" ]]; then
   xver=$(xray version 2>/dev/null | head -n 1 || true)
   die "无法识别 xray x25519 输出格式（\${xver:-Xray 版本未知}）。当前解析器兼容 Private key/Public key、PrivateKey/Password，以及 PrivateKey/Password (PublicKey) 格式；为避免写入空密钥，已停止。请勿公开完整 xray x25519 输出，因为其中包含服务端私钥"
 fi
}
# Multi-inbound 2.x manager. Each tag is independently installed/removed.
STATE_FILE="$STATE/state.json"
SOCKET=/run/xray-dual/xhttp.sock
init_v2(){
  if [[ ! -e "$STATE_FILE" && -s "$CONF" ]] && jq -e '[.inbounds[]?.tag]|any(.=="dual-ws" or .=="dual-reality")' "$CONF" >/dev/null 2>&1; then
    die "检测到 1.x 旧配置；当前版本不自动迁移，拒绝覆盖。请先备份并阅读 docs/MIGRATION_v1_to_v2.md"
  fi
  [[ -s "$STATE_FILE" ]] || printf '{"domain":"","inbounds":{}}\n' >"$STATE_FILE"
  jq -e '.inbounds|type=="object"' "$STATE_FILE" >/dev/null || die "状态文件损坏"
  if [[ ! -s "$CONF" ]]; then printf '%s\n' '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct","settings":{}},{"protocol":"blackhole","tag":"blocked","settings":{}}],"routing":{"rules":[]}}' >"$CONF"; fi
}
has(){ jq -e --arg t "$1" '.inbounds[$t]' "$STATE_FILE" >/dev/null 2>&1; }
inbound_health(){
  local t="$1"
  systemctl is-active --quiet xray || return 1
  if [[ "$t" == ws-nginx || "$t" == xhttp-nginx ]]; then
    nginx -t >/dev/null 2>&1 || return 1
    systemctl is-active --quiet nginx || return 1
  fi
}
state_add(){
  local t="$1" r="$2" f
  f=$(mktemp) || return 1
  if ! jq --arg t "$t" --argjson r "$r" '.inbounds[$t]=$r' "$STATE_FILE" >"$f" || ! jq -e '.inbounds|type=="object"' "$f" >/dev/null; then
    rm -f "$f"; return 1
  fi
  install -m 600 "$f" "$STATE_FILE" || { rm -f "$f"; return 1; }
  rm -f "$f"
}
state_del(){
  local t="$1" f
  f=$(mktemp) || return 1
  if ! jq --arg t "$t" 'del(.inbounds[$t])' "$STATE_FILE" >"$f" || ! jq -e '.inbounds|type=="object"' "$f" >/dev/null; then
    rm -f "$f"; return 1
  fi
  install -m 600 "$f" "$STATE_FILE" || { rm -f "$f"; return 1; }
  rm -f "$f"
}
make_saved_link(){
  local t="$1" id path port sni sid pbk domain ip encoded
  id=$(jq -r --arg t "$t" '.inbounds[$t].uuid // ""' "$STATE_FILE")
  path=$(jq -r --arg t "$t" '.inbounds[$t].path // ""' "$STATE_FILE")
  port=$(jq -r --arg t "$t" '.inbounds[$t].port // ""' "$STATE_FILE")
  sni=$(jq -r --arg t "$t" '.inbounds[$t].sni // ""' "$STATE_FILE")
  sid=$(jq -r --arg t "$t" '.inbounds[$t].sid // ""' "$STATE_FILE")
  pbk=$(jq -r --arg t "$t" '.inbounds[$t].pbk // ""' "$STATE_FILE")
  domain=$(jq -r '.domain // ""' "$STATE_FILE")
  encoded=$(jq -rn --arg p "$path" '$p|@uri')
  case "$t" in
    ws-nginx)
      printf 'vless://%s@%s:443?encryption=none&security=tls&type=ws&host=%s&path=%s#WS-TLS-Nginx\n' "$id" "$domain" "$domain" "$encoded";;
    tcp-reality-vision)
      ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
      printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#TCP-REALITY-Vision\n' "$id" "$ip" "$port" "$sni" "$pbk" "$sid";;
    tcp-tls-vision)
      printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=%s#TCP-TLS-Vision\n' "$id" "$domain" "$port" "$domain";;
    tcp-tls)
      printf 'vless://%s@%s:%s?encryption=none&security=tls&type=tcp&sni=%s#TCP-TLS\n' "$id" "$domain" "$port" "$domain";;
    xhttp-reality)
      ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
      printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&path=%s&mode=auto#XHTTP-REALITY\n' "$id" "$ip" "$port" "$sni" "$pbk" "$sid" "$encoded";;
    xhttp-tls)
      printf 'vless://%s@%s:%s?encryption=none&security=tls&type=xhttp&sni=%s&alpn=h2&path=%s&mode=auto#XHTTP-TLS\n' "$id" "$domain" "$port" "$domain" "$encoded";;
    xhttp-nginx)
      printf 'vless://%s@%s:443?encryption=none&security=tls&type=xhttp&host=%s&path=%s&mode=stream-one#XHTTP-TLS-Nginx\n' "$id" "$domain" "$domain" "$encoded";;
    *) return 1;;
  esac
}
refresh_saved_links(){
  local t link f
  for t in ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx; do
    has "$t" || continue
    [[ -n "$(jq -r --arg t "$t" '.inbounds[$t].link // ""' "$STATE_FILE")" ]] && continue
    link=$(make_saved_link "$t") || continue
    f=$(mktemp)
    jq --arg t "$t" --arg link "$link" '.inbounds[$t].link=$link' "$STATE_FILE" >"$f"
    install -m 600 "$f" "$STATE_FILE"
    rm -f "$f"
  done
}
inbound_add(){ local t="$1" i="$2"; jq --arg t "$t" --argjson i "$i" '.inbounds=((.inbounds//[])|map(select(.tag!=$t)))+[$i]' "$CONF" | apply_config; }
inbound_del(){ jq --arg t "$1" '.inbounds=((.inbounds//[])|map(select(.tag!=$t)))' "$CONF" | apply_config; }
domain_tls(){
  ensure_nginx_http
  DOMAIN=$(jq -r '.domain // ""' "$STATE_FILE")
  if [[ -z "$DOMAIN" ]]; then
    read -rp "TLS 域名（所有 TLS 配置共用）: " DOMAIN
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ && "$DOMAIN" == *.* ]] || die "域名格式无效"
    local f; f=$(mktemp); jq --arg d "$DOMAIN" '.domain=$d' "$STATE_FILE" >"$f"; install -m 600 "$f" "$STATE_FILE"; rm -f "$f"
  fi
  mkdir -p "$WEBROOT" "$CERTDIR"
  if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then
    if has ws-nginx || has xhttp-nginx; then
      die "检测到已登记的 Nginx 前置入站，但 TLS 证书缺失；为避免覆盖现有 WS/XHTTP 路由，停止自动签发。请先恢复证书或手动备份并修复 Nginx 配置"
    fi
    cat >"$NGINX" <<EOF
server {
 listen 80; listen [::]:80; server_name $DOMAIN; root $WEBROOT;
 location ^~ /.well-known/acme-challenge/ { default_type "text/plain"; try_files \$uri =404; }
 location / { return 404; }
}
EOF
    nginx -t && systemctl reload nginx
    acme_setup
  fi
  openssl x509 -in "$CERT" -noout -checkhost "$DOMAIN" >/dev/null 2>&1 || die "证书与 $DOMAIN 不匹配"
}
nginx_aggregate(){
  local d wp wpath xpath t
  d=$(jq -r '.domain // ""' "$STATE_FILE"); [[ -n "$d" ]] || return 0
  wp=$(jq -r '.inbounds["ws-nginx"].port // ""' "$STATE_FILE")
  wpath=$(jq -r '.inbounds["ws-nginx"].path // ""' "$STATE_FILE")
  xpath=$(jq -r '.inbounds["xhttp-nginx"].path // ""' "$STATE_FILE")
  t=$(mktemp)
  cat >"$t" <<EOF
# Managed by Xray-Dual-Protocol-OneKey
server {
 listen 80; listen [::]:80; server_name $d; root $WEBROOT;
 location ^~ /.well-known/acme-challenge/ { default_type "text/plain"; try_files \$uri =404; }
 location / { return 301 https://\$host\$request_uri; }
}
EOF
  if [[ -n "$wp" || -n "$xpath" ]]; then
    cat >>"$t" <<EOF
server {
 listen 443 ssl http2; listen [::]:443 ssl http2; server_name $d;
 ssl_certificate $CERT; ssl_certificate_key $KEY; ssl_protocols TLSv1.2 TLSv1.3;
EOF
    if [[ -n "$wp" ]]; then cat >>"$t" <<EOF
 location = $wpath {
  proxy_pass http://127.0.0.1:$wp; proxy_http_version 1.1;
  proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host;
 }
EOF
    fi
    if [[ -n "$xpath" ]]; then cat >>"$t" <<EOF
 location ^~ $xpath {
  client_max_body_size 0; grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  client_body_timeout 5m; grpc_read_timeout 315s; grpc_send_timeout 5m;
  grpc_pass unix:$SOCKET;
 }
EOF
    fi
    echo ' location / { return 404; }' >>"$t"; echo '}' >>"$t"
  fi
  local nginx_backup=""
  if [[ -e "$NGINX" ]]; then
    nginx_backup="$NGINX.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$NGINX" "$nginx_backup"
  fi
  install -m 644 "$t" "$NGINX"
  rm -f "$t"
  if ! nginx -t >/dev/null 2>&1; then
    if [[ -n "$nginx_backup" ]]; then cp -a "$nginx_backup" "$NGINX"; else rm -f "$NGINX"; fi
    nginx -t >/dev/null 2>&1 || true
    echo "[ERROR] 新 Nginx 配置测试失败，已恢复原项目配置" >&2
    return 1
  fi
  if ! systemctl reload nginx; then
    if [[ -n "$nginx_backup" ]]; then cp -a "$nginx_backup" "$NGINX"; else rm -f "$NGINX"; fi
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
    echo "[ERROR] Nginx 重载失败，已恢复原项目配置并尝试恢复旧服务" >&2
    return 1
  fi
}
check_443(){
  local lines processes
  lines=$(port_listener_lines 443)
  if [[ -n "$lines" ]]; then
    processes=$(listener_processes 443)
    if [[ "$processes" != "nginx" ]]; then
      printf '%s\n' "$lines" >&2
      die "TCP/443 已被非 Nginx 服务占用；为避免中断现有服务，停止安装"
    fi
  fi
  if has ws-nginx || has xhttp-nginx; then
    [[ -n "$lines" && "$processes" == "nginx" ]] ||
      die "已有 Nginx 前置入站，但 Nginx 当前未监听 TCP/443"
  fi
}
# Cross-component transaction helpers. Snapshot both Xray state and Nginx routes.
manager_txn_snapshot(){
  TXN_DIR=$(mktemp -d)
  cp -a "$CONF" "$TXN_DIR/config.json"
  cp -a "$STATE_FILE" "$TXN_DIR/state.json"
  [[ -e "$NGINX" ]] && cp -a "$NGINX" "$TXN_DIR/nginx.conf" || true
  [[ -e /etc/systemd/system/xray.service.d/dual-protocol.conf ]] && cp -a /etc/systemd/system/xray.service.d/dual-protocol.conf "$TXN_DIR/xray-dropin" || true
}
manager_txn_rollback(){
  cp -a "$TXN_DIR/config.json" "$CONF"
  cp -a "$TXN_DIR/state.json" "$STATE_FILE"
  if [[ -e "$TXN_DIR/nginx.conf" ]]; then cp -a "$TXN_DIR/nginx.conf" "$NGINX"; else rm -f "$NGINX"; fi
  if [[ -e "$TXN_DIR/xray-dropin" ]]; then
    mkdir -p /etc/systemd/system/xray.service.d
    cp -a "$TXN_DIR/xray-dropin" /etc/systemd/system/xray.service.d/dual-protocol.conf
  else rm -f /etc/systemd/system/xray.service.d/dual-protocol.conf; fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  xray run -test -config "$CONF" >/dev/null 2>&1 && systemctl restart xray >/dev/null 2>&1 || true
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  rm -rf "$TXN_DIR"
}
manager_txn_commit(){ rm -rf "$TXN_DIR"; }

add_ws2(){
  has ws-nginx && die "WS-Nginx 已安装"
  check_443
  domain_tls
  check_443
  manager_txn_snapshot
  local id p path rec ib
  id=$(new_uuid); p=$(shuf -i 12000-50000 -n1); path="/$(openssl rand -hex 12)/"
  rec=$(jq -n --arg id "$id" --arg path "$path" --argjson p "$p" '{uuid:$id,path:$path,port:$p}') || { manager_txn_rollback; return 1; }
  ib=$(jq -n --arg id "$id" --arg path "$path" --argjson p "$p" '{tag:"ws-nginx",listen:"127.0.0.1",port:$p,protocol:"vless",settings:{clients:[{id:$id}],decryption:"none"},streamSettings:{network:"ws",security:"none",wsSettings:{path:$path}}}') || { manager_txn_rollback; return 1; }
  if ! inbound_add ws-nginx "$ib" || ! state_add ws-nginx "$rec" || ! nginx_aggregate; then
    manager_txn_rollback
    echo "[ERROR] WS-Nginx 安装失败，Xray、状态文件和 Nginx 已尝试回滚" >&2
    return 1
  fi
  manager_txn_commit
  echo "vless://$id@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$(jq -rn --arg p "$path" '$p|@uri')#WS-TLS-Nginx"
}
add_xhttp_nginx2(){
  has xhttp-nginx && die "XHTTP-Nginx 已安装"
  check_443
  domain_tls
  check_443
  manager_txn_snapshot
  mkdir -p /etc/systemd/system/xray.service.d
  cat >/etc/systemd/system/xray.service.d/dual-protocol.conf <<'UNIT'
[Service]
Group=www-data
RuntimeDirectory=xray-dual
RuntimeDirectoryMode=0770
UNIT
  systemctl daemon-reload || { manager_txn_rollback; return 1; }
  local id path rec ib
  id=$(new_uuid); path="/$(openssl rand -hex 12)/"
  rec=$(jq -n --arg id "$id" --arg path "$path" '{uuid:$id,path:$path}') || { manager_txn_rollback; return 1; }
  ib=$(jq -n --arg id "$id" --arg path "$path" --arg sock "$SOCKET" '{tag:"xhttp-nginx",listen:($sock+",0660"),protocol:"vless",settings:{clients:[{id:$id}],decryption:"none"},streamSettings:{network:"xhttp",xhttpSettings:{mode:"stream-one",path:$path}}}') || { manager_txn_rollback; return 1; }
  if ! inbound_add xhttp-nginx "$ib" || ! state_add xhttp-nginx "$rec" || ! nginx_aggregate; then
    manager_txn_rollback
    echo "[ERROR] XHTTP-Nginx 安装失败，Xray、状态、Nginx 和 systemd drop-in 已尝试回滚" >&2
    return 1
  fi
  manager_txn_commit
  echo "vless://$id@$DOMAIN:443?encryption=none&security=tls&type=xhttp&host=$DOMAIN&path=$(jq -rn --arg p "$path" '$p|@uri')&mode=stream-one#XHTTP-TLS-Nginx"
}
add_direct2(){
  local mode="$1" tag net sec flow def p id path ib rec
  case "$mode" in
    reality) tag=tcp-reality-vision; net=tcp; sec=reality; flow=xtls-rprx-vision; def=8443;;
    tlsvision) tag=tcp-tls-vision; net=tcp; sec=tls; flow=xtls-rprx-vision; def=8444;;
    tls) tag=tcp-tls; net=tcp; sec=tls; flow=""; def=8445;;
    xreality) tag=xhttp-reality; net=xhttp; sec=reality; flow=""; def=8446;;
    xtls) tag=xhttp-tls; net=xhttp; sec=tls; flow=""; def=8447;;
  esac
  has "$tag" && die "$tag 已安装"
  [[ "$sec" == tls ]] && domain_tls
  read -rp "本机监听端口 [$def]（客户端连接 VPS 时使用的端口）: " p; [[ -n "$p" ]] || p="$def"
  [[ "$p" =~ ^[0-9]+$ ]] && ((p>0&&p<65536)) || die "端口无效"
  ! ss -H -lnt "( sport = :$p )" 2>/dev/null|grep -q . || die "端口 $p 已占用"
  id=$(new_uuid); path="/$(openssl rand -hex 12)/"
  if [[ "$sec" == reality ]]; then
    local dest dp sni sid
    read -rp "REALITY dest 主机名（只填域名/IP，不含端口，例如 www.calstatela.edu）: " dest
    [[ "$dest" =~ ^[A-Za-z0-9.-]+$ && "$dest" != .* && "$dest" != *. && "$dest" != *..* ]] ||
      die "dest 格式无效：这里只填主机名，不要填写 :端口；端口会在下一步单独输入"
    read -rp "dest 端口 [443]（目标网站端口，通常为 443）: " dp; dp=${dp:-443}
    valid_port "$dp" || die "dest 端口无效，请输入 1–65535 的数字"
    read -rp "SNI [$dest]（留空则使用 dest 主机名）: " sni; sni=${sni:-$dest}
    [[ "$sni" =~ ^[A-Za-z0-9.-]+$ && "$sni" != .* && "$sni" != *. && "$sni" != *..* ]] ||
      die "SNI 格式无效：这里只填写主机名，不要添加端口"
    sid=$(openssl rand -hex 8); reality_keys
    ib=$(jq -n --arg id "$id" --argjson p "$p" --arg net "$net" --arg path "$path" --arg dest "$dest:$dp" --arg sni "$sni" --arg sid "$sid" --arg pk "$R_PRIV" --arg flow "$flow" --arg tag "$tag" '{tag:$tag,listen:"0.0.0.0",port:$p,protocol:"vless",settings:{clients:([{id:$id}]|if $flow!="" then .[0].flow=$flow else . end),decryption:"none"},streamSettings:({network:$net,security:"reality",realitySettings:{show:false,dest:$dest,xver:0,serverNames:[$sni],privateKey:$pk,shortIds:[$sid]}}+(if $net=="xhttp" then {xhttpSettings:{mode:"auto",path:$path}} else {} end))}')
    rec=$(jq -n --arg id "$id" --arg path "$path" --arg sni "$sni" --arg sid "$sid" --arg pbk "$R_PUB" --arg dest "$dest" --argjson dp "$dp" --argjson p "$p" '{uuid:$id,path:$path,port:$p,sni:$sni,sid:$sid,pbk:$pbk,dest:$dest,dest_port:$dp}')
  else
    ib=$(jq -n --arg id "$id" --argjson p "$p" --arg net "$net" --arg path "$path" --arg cert "$CERT" --arg key "$KEY" --arg flow "$flow" --arg tag "$tag" '{tag:$tag,listen:"0.0.0.0",port:$p,protocol:"vless",settings:{clients:([{id:$id}]|if $flow!="" then .[0].flow=$flow else . end),decryption:"none"},streamSettings:({network:$net,security:"tls",tlsSettings:({certificates:[{certificateFile:$cert,keyFile:$key}]}+(if $net=="xhttp" then {alpn:["h2"]} else {} end))}+(if $net=="xhttp" then {xhttpSettings:{mode:"auto",path:$path}} else {} end))}')
    rec=$(jq -n --arg id "$id" --arg path "$path" --argjson p "$p" '{uuid:$id,path:$path,port:$p}')
  fi
  manager_txn_snapshot
  if ! inbound_add "$tag" "$ib" || ! state_add "$tag" "$rec"; then
    manager_txn_rollback
    echo "[ERROR] $tag 安装失败，Xray 与状态文件已尝试回滚" >&2
    return 1
  fi
  manager_txn_commit
  local ip; ip=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null||hostname -I|awk '{print $1}')
  if [[ "$sec" == reality && "$net" == xhttp ]]; then
    echo "vless://$id@$ip:$p?encryption=none&security=reality&sni=$sni&fp=chrome&pbk=$R_PUB&sid=$sid&type=xhttp&path=$(jq -rn --arg p "$path" '$p|@uri')&mode=auto#XHTTP-REALITY"
  elif [[ "$sec" == reality ]]; then
    echo "vless://$id@$ip:$p?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$R_PUB&sid=$sid&type=tcp#TCP-REALITY-Vision"
  elif [[ "$net" == xhttp ]]; then
    echo "vless://$id@$DOMAIN:$p?encryption=none&security=tls&type=xhttp&sni=$DOMAIN&alpn=h2&path=$(jq -rn --arg p "$path" '$p|@uri')&mode=auto#XHTTP-TLS"
  elif [[ -n "$flow" ]]; then
    echo "vless://$id@$DOMAIN:$p?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=$DOMAIN#TCP-TLS-Vision"
  else
    echo "vless://$id@$DOMAIN:$p?encryption=none&security=tls&type=tcp&sni=$DOMAIN#TCP-TLS"
  fi
}
remove_v2(){
  local t="$1"
  has "$t" || die "$t 未安装"
  manager_txn_snapshot
  if ! inbound_del "$t" || ! state_del "$t" || ! nginx_aggregate; then
    manager_txn_rollback
    echo "[ERROR] $t 卸载失败，已尝试恢复原配置和其他 Nginx 路由" >&2
    return 1
  fi
  if [[ "$t" == xhttp-nginx ]]; then
    rm -f /etc/systemd/system/xray.service.d/dual-protocol.conf
    systemctl daemon-reload
    if ! systemctl restart xray || ! systemctl is-active --quiet xray; then
      manager_txn_rollback
      echo "[ERROR] XHTTP-Nginx 卸载后 Xray 服务异常，已尝试回滚" >&2
      return 1
    fi
  fi
  manager_txn_commit
  ok "$t 已卸载；其他入站保留"
}
show_v2(){
  jq -r '.inbounds|to_entries[]|[.key,(.value.port//"-"|tostring),(.value.path//"-")]|@tsv' "$STATE_FILE"
  jq -r '.inbounds[]?|[.tag,.listen//"0.0.0.0",(.port//"unix"),.streamSettings.network//"tcp",.streamSettings.security//"none"]|@tsv' "$CONF"
}
# Interactive installation UX: one inbound at a time, verified before advancing.
INSTALL_MODE=0
INSTALL_CURRENT=""
INSTALL_TEE_PID=""
declare -a INSTALL_OK_LABELS=()
install_summary(){
  local rc="$1" tag link
  [[ "$INSTALL_MODE" == 1 ]] || return 0
  if [[ -n "$INSTALL_TEE_PID" ]]; then
    exec 3>&- || true
    wait "$INSTALL_TEE_PID" || true
    INSTALL_TEE_PID=""
  fi
  echo
  echo "================ 安装结果汇总 ================"
  if (( rc == 0 )); then
    echo "[完成] 本次安装流程已结束"
  else
    echo "[中断] 安装在「${INSTALL_CURRENT:-未知步骤}」处失败；后续项目未继续执行"
  fi
  if (("${#INSTALL_OK_LABELS[@]}" > 0)); then
    echo "本次新安装成功：${#INSTALL_OK_LABELS[@]} 项"
  fi
  echo
  echo "当前服务器所有已登记配置及客户端链接："
  for tag in ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx; do
    if has "$tag"; then
      link=$(jq -r --arg t "$tag" '.inbounds[$t].link // ""' "$STATE_FILE" 2>/dev/null || true)
      if ! jq -e --arg t "$tag" '.inbounds[]? | select(.tag==$t)' "$CONF" >/dev/null 2>&1; then
        printf '  [异常] %s（状态记录存在，但 Xray 入站缺失）\n' "$tag"
      elif ! inbound_health "$tag"; then
        printf '  [服务异常] %s（Xray 或该模式依赖的 Nginx 未正常运行）\n' "$tag"
      elif [[ -n "$link" ]]; then
        printf '\n  [已运行] %s\n  %s\n' "$tag" "$link"
      else
        printf '  [需检查] %s（配置存在，但客户端链接缺失）\n' "$tag"
      fi
    else
      printf '  [未安装] %s\n' "$tag"
    fi
  done
  echo "================================================"
}
trap 'install_summary "$?"' EXIT

show_install_status(){
  local -a tags=(ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx)
  local -a labels=("WS + TLS + Nginx" "TCP + REALITY + Vision" "TCP + TLS + Vision" "TCP + TLS" "XHTTP + REALITY" "XHTTP + TLS" "XHTTP + TLS + Nginx")
  local i tag
  echo "---------------- 当前安装状态 ----------------"
  for i in "${!tags[@]}"; do
    tag="${tags[$i]}"
    if has "$tag"; then
      if ! jq -e --arg t "$tag" '.inbounds[]? | select(.tag==$t)' "$CONF" >/dev/null 2>&1; then
        printf '  [异常]   %s（状态记录与 Xray 配置不一致）\n' "${labels[$i]}"
      elif inbound_health "$tag"; then
        printf '  [已运行] %s\n' "${labels[$i]}"
      else
        printf '  [服务异常] %s（Xray 或该模式依赖的 Nginx 未正常运行）\n' "${labels[$i]}"
      fi
    else
      printf '  [未安装] %s\n' "${labels[$i]}"
    fi
  done
  echo "------------------------------------------------"
}

install_one(){
  local label="$1" tag="$2" fn="$3" tmp link
  INSTALL_MODE=1
  INSTALL_CURRENT="$label"
  if has "$tag"; then
    if jq -e --arg t "$tag" '.inbounds[]? | select(.tag==$t)' "$CONF" >/dev/null 2>&1; then
      inbound_health "$tag" || die "$label：配置记录存在，但 Xray/Nginx 服务未通过运行状态检查；请先排查服务，不会重复安装"
      echo "[跳过] $label：Xray 入站和所需服务均正常"
      INSTALL_CURRENT=""
      return 0
    fi
    die "$label：发现状态记录，但 Xray 入站不存在。为避免覆盖或误判，已停止；请先查看配置状态并处理异常记录"
  fi
  echo
  echo "================================================"
  echo "正在安装：$label"
  echo "配置标识：$tag"
  echo "================================================"
  tmp=$(mktemp)
  echo "[进行中] 步骤 1/3：执行 $label 安装与配置写入（日志实时显示；交互提示直接显示在终端）"
  exec 3> >(tee "$tmp" | sed -u '/^vless:\/\//d')
  INSTALL_TEE_PID=$!
  # Only redirect stdout through the log pipeline. Keep stderr attached to
  # the terminal so read -rp prompts and actionable errors remain visible.
  "$fn" >&3
  exec 3>&-
  wait "$INSTALL_TEE_PID" || true
  INSTALL_TEE_PID=""
  echo "[完成] 步骤 1/3：安装函数已返回"
  echo "[进行中] 步骤 2/3：验证 Xray 配置及服务状态"
  xray run -test -config "$CONF" >/dev/null || { rm -f "$tmp"; echo "[失败] Xray 配置校验未通过" >&2; return 1; }
  systemctl is-active --quiet xray || { rm -f "$tmp"; echo "[失败] Xray 服务未处于 active 状态" >&2; return 1; }
  if [[ "$tag" == ws-nginx || "$tag" == xhttp-nginx ]]; then
    nginx -t >/dev/null || { rm -f "$tmp"; echo "[失败] Nginx 配置校验未通过" >&2; return 1; }
    systemctl is-active --quiet nginx || { rm -f "$tmp"; echo "[失败] Nginx 服务未处于 active 状态" >&2; return 1; }
  fi
  echo "[完成] 步骤 2/3：Xray 配置及服务状态验证通过"
  echo "[进行中] 步骤 3/3：检查安装状态并保存客户端链接"
  has "$tag" || { rm -f "$tmp"; echo "[失败] 未发现预期的安装状态记录" >&2; return 1; }
  link=$(grep -E '^vless://' "$tmp" | tail -n 1 || true)
  rm -f "$tmp"
  [[ -n "$link" ]] || { echo "[失败] 未生成 VLESS 客户端链接" >&2; return 1; }
  local state_tmp
  state_tmp=$(mktemp)
  jq --arg t "$tag" --arg link "$link" '.inbounds[$t].link=$link' "$STATE_FILE" >"$state_tmp"
  install -m 600 "$state_tmp" "$STATE_FILE"
  rm -f "$state_tmp"
  INSTALL_OK_LABELS+=("$label")
  INSTALL_CURRENT=""
  echo "[完成] 步骤 3/3：安装状态和客户端链接已保存"
  echo "[成功] $label 已安装并通过基础验收"
}

all_v2(){
  install_one "1/7  VLESS + WS + TLS + Nginx" ws-nginx add_ws2
  install_one "2/7  VLESS + TCP + REALITY + Vision" tcp-reality-vision add_direct2_reality
  install_one "3/7  VLESS + TCP + TLS + Vision" tcp-tls-vision add_direct2_tlsvision
  install_one "4/7  VLESS + TCP + TLS" tcp-tls add_direct2_tls
  install_one "5/7  VLESS + XHTTP + REALITY" xhttp-reality add_direct2_xreality
  install_one "6/7  VLESS + XHTTP + TLS" xhttp-tls add_direct2_xtls
  install_one "7/7  VLESS + XHTTP + TLS + Nginx" xhttp-nginx add_xhttp_nginx2
}
# Adapters keep each installation function's original parameters explicit.
add_direct2_reality(){ add_direct2 reality; }
add_direct2_tlsvision(){ add_direct2 tlsvision; }
add_direct2_tls(){ add_direct2 tls; }
add_direct2_xreality(){ add_direct2 xreality; }
add_direct2_xtls(){ add_direct2 xtls; }

menu_v2(){
  echo "Xray Dual Protocol OneKey v$PROJECT_VERSION"
  show_install_status
  echo '1 安装 WS+TLS+Nginx'
  echo '2 安装 TCP+REALITY+Vision'
  echo '3 安装 TCP+TLS+Vision'
  echo '4 安装 TCP+TLS'
  echo '5 安装 XHTTP+REALITY'
  echo '6 安装 XHTTP+TLS'
  echo '7 安装 XHTTP+TLS+Nginx'
  echo '8 按顺序安装全部七种（每项验收通过后才进入下一项）'
  echo '9 查看配置  10 卸载单项  11 证书状态  0 退出'
  read -rp '选择: ' n
  case "$n" in
    1) install_one "VLESS + WS + TLS + Nginx" ws-nginx add_ws2;;
    2) install_one "VLESS + TCP + REALITY + Vision" tcp-reality-vision add_direct2_reality;;
    3) install_one "VLESS + TCP + TLS + Vision" tcp-tls-vision add_direct2_tlsvision;;
    4) install_one "VLESS + TCP + TLS" tcp-tls add_direct2_tls;;
    5) install_one "VLESS + XHTTP + REALITY" xhttp-reality add_direct2_xreality;;
    6) install_one "VLESS + XHTTP + TLS" xhttp-tls add_direct2_xtls;;
    7) install_one "VLESS + XHTTP + TLS + Nginx" xhttp-nginx add_xhttp_nginx2;;
    8) all_v2;;
    9) show_v2;;
    10) echo '1 WS-Nginx 2 TCP-REALITY-Vision 3 TCP-TLS-Vision 4 TCP-TLS 5 XHTTP-REALITY 6 XHTTP-TLS 7 XHTTP-Nginx'; read -rp '编号: ' r
      case "$r" in 1) remove_v2 ws-nginx;; 2) remove_v2 tcp-reality-vision;; 3) remove_v2 tcp-tls-vision;; 4) remove_v2 tcp-tls;; 5) remove_v2 xhttp-reality;; 6) remove_v2 xhttp-tls;; 7) remove_v2 xhttp-nginx;; *) die '无效选项';; esac;;
    11) "$HOME/.acme.sh/acme.sh" --list 2>/dev/null||true; openssl x509 -in "$CERT" -noout -dates 2>/dev/null||true;;
    0) exit 0;;
    *) die '无效选项';;
  esac
}
install_deps
init_v2
install_xray
refresh_saved_links
# Load the versioned management panel shipped alongside this installer.
MANAGEMENT_LIB=/usr/local/lib/xray-dual-protocol/management.sh
mkdir -p "$(dirname "$MANAGEMENT_LIB")"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/feature/seven-inbound-modes/lib/management.sh" -o "$MANAGEMENT_LIB"
chmod 600 "$MANAGEMENT_LIB"
source "$MANAGEMENT_LIB"
menu_v2


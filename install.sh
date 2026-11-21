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
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates jq nginx cron openssl iproute2
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
 listen 443 ssl http2;
 listen [::]:443 ssl;
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
 # Ensure a valid base Xray config exists before the ACME deploy hook runs.
 if [[ ! -s "$CONF" ]]; then
   printf '%s\n' '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"blocked"}],"routing":{"rules":[]}}' >"$CONF"
   chmod 600 "$CONF"
 fi
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
state_add(){ local t="$1" r="$2" f; f=$(mktemp); jq --arg t "$t" --argjson r "$r" '.inbounds[$t]=$r' "$STATE_FILE" >"$f"; install -m 600 "$f" "$STATE_FILE"; rm -f "$f"; }
state_del(){ local t="$1" f; f=$(mktemp); jq --arg t "$t" 'del(.inbounds[$t])' "$STATE_FILE" >"$f"; install -m 600 "$f" "$STATE_FILE"; rm -f "$f"; }
inbound_add(){ local t="$1" i="$2"; jq --arg t "$t" --argjson i "$i" '.inbounds=((.inbounds//[])|map(select(.tag!=$t)))+[$i]' "$CONF" | apply_config; }
inbound_del(){ jq --arg t "$1" '.inbounds=((.inbounds//[])|map(select(.tag!=$t)))' "$CONF" | apply_config; }
domain_tls(){
  DOMAIN=$(jq -r '.domain // ""' "$STATE_FILE")
  if [[ -z "$DOMAIN" ]]; then
    read -rp "TLS 域名（所有 TLS 配置共用）: " DOMAIN
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ && "$DOMAIN" == *.* ]] || die "域名格式无效"
    local f; f=$(mktemp); jq --arg d "$DOMAIN" '.domain=$d' "$STATE_FILE" >"$f"; install -m 600 "$f" "$STATE_FILE"; rm -f "$f"
  fi
  mkdir -p "$WEBROOT" "$CERTDIR"
  if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then
    cat >"$NGINX" <<EOF
server {
 listen 80; listen [::]:80; server_name $DOMAIN; root $WEBROOT;
 location ^~ /.well-known/acme-challenge/ { default_type "text/plain"; try_files \\$uri =404; }
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
 location ^~ /.well-known/acme-challenge/ { default_type "text/plain"; try_files \\$uri =404; }
 location / { return 301 https://\\$host\\$request_uri; }
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
  proxy_set_header Upgrade \\$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \\$host;
 }
EOF
    fi
    if [[ -n "$xpath" ]]; then cat >>"$t" <<EOF
 location ^~ $xpath {
  client_max_body_size 0; grpc_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
  client_body_timeout 5m; grpc_read_timeout 315s; grpc_send_timeout 5m;
  grpc_pass unix:$SOCKET;
 }
EOF
    fi
    echo ' location / { return 404; }' >>"$t"; echo '}' >>"$t"
  fi
  [[ -e "$NGINX" ]] && cp -a "$NGINX" "$NGINX.bak.$(date +%Y%m%d%H%M%S)"
  install -m 644 "$t" "$NGINX"; rm -f "$t"
  nginx -t || die "Nginx 配置测试失败，旧配置备份已保留"
  systemctl reload nginx
}
check_443(){
  if has ws-nginx || has xhttp-nginx; then ss -lntp 2>/dev/null|grep -q nginx || die "现有 Nginx 前置 443 未监听"
  else ! ss -H -lnt "( sport = :443 )" 2>/dev/null|grep -q . || die "443 端口已占用"
  fi
}
add_ws2(){
  has ws-nginx && die "WS-Nginx 已安装"; check_443; domain_tls
  local id p path rec ib; id=$(new_uuid); p=$(shuf -i 12000-50000 -n1); path="/$(openssl rand -hex 12)/"
  rec=$(jq -n --arg id "$id" --arg path "$path" --argjson p "$p" '{uuid:$id,path:$path,port:$p}')
  ib=$(jq -n --arg id "$id" --arg path "$path" --argjson p "$p" '{tag:"ws-nginx",listen:"127.0.0.1",port:$p,protocol:"vless",settings:{clients:[{id:$id}],decryption:"none"},streamSettings:{network:"ws",security:"none",wsSettings:{path:$path}}}')
  inbound_add ws-nginx "$ib"; state_add ws-nginx "$rec"; nginx_aggregate
  echo "vless://$id@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$(jq -rn --arg p "$path" '$p|@uri')#WS-TLS-Nginx"
}
add_xhttp_nginx2(){
  has xhttp-nginx && die "XHTTP-Nginx 已安装"; check_443; domain_tls
  mkdir -p /etc/systemd/system/xray.service.d
  cat >/etc/systemd/system/xray.service.d/dual-protocol.conf <<'UNIT'
[Service]
Group=www-data
RuntimeDirectory=xray-dual
RuntimeDirectoryMode=0770
UNIT
  systemctl daemon-reload
  local id path rec ib; id=$(new_uuid); path="/$(openssl rand -hex 12)/"
  rec=$(jq -n --arg id "$id" --arg path "$path" '{uuid:$id,path:$path}')
  ib=$(jq -n --arg id "$id" --arg path "$path" --arg sock "$SOCKET" '{tag:"xhttp-nginx",listen:($sock+",0660"),protocol:"vless",settings:{clients:[{id:$id}],decryption:"none"},streamSettings:{network:"xhttp",xhttpSettings:{mode:"stream-one",path:$path}}}')
  inbound_add xhttp-nginx "$ib"; state_add xhttp-nginx "$rec"; nginx_aggregate
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
  read -rp "监听端口 [$def]: " p; [[ -n "$p" ]] || p="$def"
  [[ "$p" =~ ^[0-9]+$ ]] && ((p>0&&p<65536)) || die "端口无效"
  ! ss -H -lnt "( sport = :$p )" 2>/dev/null|grep -q . || die "端口 $p 已占用"
  id=$(new_uuid); path="/$(openssl rand -hex 12)/"
  if [[ "$sec" == reality ]]; then
    local dest dp sni sid; read -rp "REALITY dest 域名: " dest
    read -rp "dest 端口 [443]: " dp; [[ -n "$dp" ]] || dp=443
    read -rp "SNI [$dest]: " sni; [[ -n "$sni" ]] || sni="$dest"
    sid=$(openssl rand -hex 8); reality_keys
    ib=$(jq -n --arg id "$id" --argjson p "$p" --arg net "$net" --arg path "$path" --arg dest "$dest:$dp" --arg sni "$sni" --arg sid "$sid" --arg pk "$R_PRIV" --arg flow "$flow" --arg tag "$tag" '{tag:$tag,listen:"0.0.0.0",port:$p,protocol:"vless",settings:{clients:([{id:$id}]|if $flow!="" then .[0].flow=$flow else . end),decryption:"none"},streamSettings:({network:$net,security:"reality",realitySettings:{show:false,dest:$dest,xver:0,serverNames:[$sni],privateKey:$pk,shortIds:[$sid]}}+(if $net=="xhttp" then {xhttpSettings:{mode:"auto",path:$path}} else {} end))}')
    rec=$(jq -n --arg id "$id" --arg path "$path" --arg sni "$sni" --arg sid "$sid" --arg pbk "$R_PUB" --argjson p "$p" '{uuid:$id,path:$path,port:$p,sni:$sni,sid:$sid,pbk:$pbk}')
  else
    ib=$(jq -n --arg id "$id" --argjson p "$p" --arg net "$net" --arg path "$path" --arg cert "$CERT" --arg key "$KEY" --arg flow "$flow" --arg tag "$tag" '{tag:$tag,listen:"0.0.0.0",port:$p,protocol:"vless",settings:{clients:([{id:$id}]|if $flow!="" then .[0].flow=$flow else . end),decryption:"none"},streamSettings:({network:$net,security:"tls",tlsSettings:({certificates:[{certificateFile:$cert,keyFile:$key}]}+(if $net=="xhttp" then {alpn:["h2"]} else {} end))}+(if $net=="xhttp" then {xhttpSettings:{mode:"auto",path:$path}} else {} end))}')
    rec=$(jq -n --arg id "$id" --arg path "$path" --argjson p "$p" '{uuid:$id,path:$path,port:$p}')
  fi
  inbound_add "$tag" "$ib"; state_add "$tag" "$rec"
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
  local t="$1"; has "$t" || die "$t 未安装"
  inbound_del "$t"; state_del "$t"; nginx_aggregate
  ok "$t 已卸载；其他入站保留"
}
show_v2(){
  jq -r '.inbounds|to_entries[]|[.key,(.value.port//"-"|tostring),(.value.path//"-")]|@tsv' "$STATE_FILE"
  jq -r '.inbounds[]?|[.tag,.listen//"0.0.0.0",(.port//"unix"),.streamSettings.network//"tcp",.streamSettings.security//"none"]|@tsv' "$CONF"
}
all_v2(){
  has ws-nginx || add_ws2
  has tcp-reality-vision || add_direct2 reality
  has tcp-tls-vision || add_direct2 tlsvision
  has tcp-tls || add_direct2 tls
  has xhttp-reality || add_direct2 xreality
  has xhttp-tls || add_direct2 xtls
  has xhttp-nginx || add_xhttp_nginx2
}
menu_v2(){
  echo '1 WS+TLS+Nginx  2 TCP+REALITY+Vision  3 TCP+TLS+Vision  4 TCP+TLS'
  echo '5 XHTTP+REALITY  6 XHTTP+TLS  7 XHTTP+TLS+Nginx  8 安装全部七种'
  echo '9 查看配置  10 卸载单项  11 证书状态  0 退出'
  read -rp '选择: ' n
  case "$n" in
    1) add_ws2;; 2) add_direct2 reality;; 3) add_direct2 tlsvision;; 4) add_direct2 tls;;
    5) add_direct2 xreality;; 6) add_direct2 xtls;; 7) add_xhttp_nginx2;; 8) all_v2;;
    9) show_v2;;
    10) echo '1 WS-Nginx 2 TCP-REALITY-Vision 3 TCP-TLS-Vision 4 TCP-TLS 5 XHTTP-REALITY 6 XHTTP-TLS 7 XHTTP-Nginx'; read -rp '编号: ' r
      case "$r" in 1) remove_v2 ws-nginx;; 2) remove_v2 tcp-reality-vision;; 3) remove_v2 tcp-tls-vision;; 4) remove_v2 tcp-tls;; 5) remove_v2 xhttp-reality;; 6) remove_v2 xhttp-tls;; 7) remove_v2 xhttp-nginx;; *) die '无效选项';; esac;;
    11) "$HOME/.acme.sh/acme.sh" --list 2>/dev/null||true; openssl x509 -in "$CERT" -noout -dates 2>/dev/null||true;;
    0) exit 0;; *) die '无效选项';;
  esac
}
init_v2
install_deps
install_xray
menu_v2


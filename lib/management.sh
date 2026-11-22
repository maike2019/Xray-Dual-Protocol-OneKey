#!/usr/bin/env bash
# Management panel; sourced by install.sh after core functions.
set -o pipefail
MGR_BACKUPS=/var/backups/xray-dual-protocol
MGR_TAGS=(ws-nginx tcp-reality-vision tcp-tls-vision tcp-tls xhttp-reality xhttp-tls xhttp-nginx)
MGR_NAMES=("WS + TLS + Nginx" "TCP + REALITY + Vision" "TCP + TLS + Vision" "TCP + TLS" "XHTTP + REALITY" "XHTTP + TLS" "XHTTP + TLS + Nginx")
mgr_status(){
 local n=0 t
 for t in "${MGR_TAGS[@]}"; do has "$t" && ((n+=1)); done
 echo "========== 服务状态 =========="
 systemctl is-active --quiet xray && echo "Xray       : 运行正常" || echo "Xray       : 未运行/异常"
 systemctl is-active --quiet nginx && echo "Nginx      : 运行正常" || echo "Nginx      : 未运行/异常"
 if [[ -s "$CERT" ]] && openssl x509 -in "$CERT" -noout -checkend 0 >/dev/null 2>&1; then echo "TLS 证书   : 有效"; else echo "TLS 证书   : 未安装/无效"; fi
 echo "已安装配置 : $n / 7"; echo "=============================="
}
mgr_select(){
 local i
 for i in "${!MGR_TAGS[@]}"; do
   if has "${MGR_TAGS[$i]}"; then printf '%d. %s [已安装]\n' "$((i+1))" "${MGR_NAMES[$i]}"
   else printf '%d. %s [未安装]\n' "$((i+1))" "${MGR_NAMES[$i]}"; fi
 done
 read -rp "选择配置（1-7，0 返回）: " MGR_CHOICE
 [[ "$MGR_CHOICE" == 0 ]] && return 1
 [[ "$MGR_CHOICE" =~ ^[1-7]$ ]] || { echo "编号无效"; return 1; }
 MGR_INDEX=$((MGR_CHOICE-1)); MGR_TAG="${MGR_TAGS[$MGR_INDEX]}"; MGR_NAME="${MGR_NAMES[$MGR_INDEX]}"
}
mgr_install(){
 mgr_select || return 0
 case "$MGR_TAG" in
 ws-nginx) install_one "$MGR_NAME" "$MGR_TAG" add_ws2;;
 tcp-reality-vision) install_one "$MGR_NAME" "$MGR_TAG" add_direct2_reality;;
 tcp-tls-vision) install_one "$MGR_NAME" "$MGR_TAG" add_direct2_tlsvision;;
 tcp-tls) install_one "$MGR_NAME" "$MGR_TAG" add_direct2_tls;;
 xhttp-reality) install_one "$MGR_NAME" "$MGR_TAG" add_direct2_xreality;;
 xhttp-tls) install_one "$MGR_NAME" "$MGR_TAG" add_direct2_xtls;;
 xhttp-nginx) install_one "$MGR_NAME" "$MGR_TAG" add_xhttp_nginx2;;
 esac
}
mgr_list(){
 local i t p net st
 printf '%-4s %-28s %-13s %-9s %-8s\n' 编号 配置 状态 端口 传输
 for i in "${!MGR_TAGS[@]}"; do
  t="${MGR_TAGS[$i]}"
  if ! has "$t"; then st=未安装; p=-; net=-
  elif ! jq -e --arg t "$t" '.inbounds[]?|select(.tag==$t)' "$CONF" >/dev/null; then st=状态不一致; p=-; net=-
  else
   if inbound_health "$t"; then st=服务正常; else st=服务异常; fi
   p=$(jq -r --arg t "$t" '.inbounds[]?|select(.tag==$t)|(.port//"unix")' "$CONF"|head -n1)
   net=$(jq -r --arg t "$t" '.inbounds[]?|select(.tag==$t)|(.streamSettings.network//"-")' "$CONF"|head -n1)
  fi
  printf '%-4s %-28s %-13s %-9s %-8s\n' "$((i+1))" "${MGR_NAMES[$i]}" "$st" "$p" "$net"
 done
}
mgr_links(){
 local t
 for t in "${MGR_TAGS[@]}"; do
   has "$t" || continue
   if ! jq -e --arg t "$t" '.inbounds[]?|select(.tag==$t)' "$CONF" >/dev/null 2>&1; then echo "[$t] 状态异常：Xray 入站缺失"; continue; fi
   echo "[$t]"; make_saved_link "$t" || echo "链接生成失败"
 done
}
mgr_qr(){
 command -v qrencode >/dev/null || { echo "请安装 qrencode"; return 1; }
 local t l
 for t in "${MGR_TAGS[@]}"; do
   has "$t" || continue
   jq -e --arg t "$t" '.inbounds[]?|select(.tag==$t)' "$CONF" >/dev/null 2>&1 || { echo "[$t] 状态异常，跳过"; continue; }
   l=$(make_saved_link "$t") || { echo "[$t] 链接生成失败"; continue; }
   echo "[$t]"; qrencode -t ANSIUTF8 -m 1 "$l"
 done
}
mgr_services(){
 local s a u v; local -a units=()
 echo "1 Xray  2 Nginx  3 两者"; read -rp "选择服务（0 返回）: " s
 [[ "$s" == 0 ]] && return
 case "$s" in 1) units=(xray);; 2) units=(nginx);; 3) units=(xray nginx);; *) echo 无效; return 1;; esac
 echo "1 启动  2 停止  3 重启"; read -rp "操作: " a
 case "$a" in 1) v=start;; 2) v=stop;; 3) v=restart;; *) echo 无效; return 1;; esac
 if [[ "$v" == stop && " ${units[*]} " == *" nginx "* ]] && { has ws-nginx || has xhttp-nginx; }; then read -rp "停止 Nginx 会中断前置入站，确认？[y/N] " a; [[ "$a" == [yY] ]] || return; fi
 for u in "${units[@]}"; do systemctl "$v" "$u" || echo "$u 操作失败"; done
}
mgr_logs(){
 local s n u; echo "1 Xray  2 Nginx"; read -rp "选择日志（0 返回）: " s
 case "$s" in 1) u=xray;; 2) u=nginx;; 0) return;; *) echo 无效; return 1;; esac
 read -rp "最近行数 [100]: " n; n="${n:-100}"
 [[ "$n" =~ ^[1-9][0-9]{0,4}$ ]] || { echo 行数无效; return 1; }
 journalctl -u "$u" -n "$n" --no-pager
}
mgr_health(){
 local bad=0 t p domain
 echo "========== 配置健康检查 =========="
 if jq -e '.inbounds|type=="object"' "$STATE_FILE" >/dev/null 2>&1; then echo "[通过] 项目状态 JSON"; else echo "[失败] 项目状态 JSON"; ((bad+=1)); fi
 if xray_test >/dev/null 2>&1; then echo "[通过] Xray 配置语法及服务账户读取权限"; else echo "[失败] Xray 配置语法"; ((bad+=1)); fi
 if systemctl is-active --quiet xray; then echo "[通过] Xray 服务运行"; else echo "[失败] Xray 服务未运行"; ((bad+=1)); fi
 if nginx -t >/dev/null 2>&1; then echo "[通过] Nginx 配置语法"; else echo "[失败] Nginx 配置语法"; ((bad+=1)); fi
 if has ws-nginx || has xhttp-nginx; then
   if systemctl is-active --quiet nginx; then echo "[通过] Nginx 前置服务运行"; else echo "[失败] Nginx 前置服务未运行"; ((bad+=1)); fi
 fi
 domain=$(jq -r '.domain // ""' "$STATE_FILE")
 if [[ -n "$domain" && ( -s "$CERT" ) ]]; then
   if openssl x509 -in "$CERT" -noout -checkhost "$domain" >/dev/null 2>&1 && openssl x509 -in "$CERT" -noout -checkend 0 >/dev/null 2>&1; then echo "[通过] TLS 证书匹配域名且未过期"; else echo "[失败] TLS 证书不匹配或已过期"; ((bad+=1)); fi
 elif [[ -n "$domain" ]]; then echo "[失败] 状态中记录域名但证书缺失"; ((bad+=1)); fi
 for t in "${MGR_TAGS[@]}"; do
   if has "$t"; then
     if jq -e --arg t "$t" '.inbounds[]?|select(.tag==$t)' "$CONF" >/dev/null 2>&1; then echo "[通过] $t 入站存在"; else echo "[失败] $t 状态记录与 Xray 入站不一致"; ((bad+=1)); fi
   fi
 done
 if has ws-nginx; then
   p=$(jq -r '.inbounds["ws-nginx"].path // ""' "$STATE_FILE")
   if [[ -n "$p" ]] && grep -Fq "location = $p" "$NGINX"; then echo "[通过] WS Nginx 路由"; else echo "[失败] WS Nginx 路由缺失"; ((bad+=1)); fi
 fi
 if has xhttp-nginx; then
   p=$(jq -r '.inbounds["xhttp-nginx"].path // ""' "$STATE_FILE")
   if [[ -n "$p" ]] && grep -Fq "location ^~ $p" "$NGINX"; then echo "[通过] XHTTP Nginx 路由"; else echo "[失败] XHTTP Nginx 路由缺失"; ((bad+=1)); fi
   if [[ -S "$SOCKET" ]]; then echo "[通过] XHTTP Unix Socket 存在"; else echo "[失败] XHTTP Unix Socket 不存在"; ((bad+=1)); fi
 fi
 echo "健康检查结束，问题数：$bad"
 echo "注意：该检查是本机配置/服务检查，不代表公网链路或客户端握手成功"
 echo "=================================="
 return "$((bad>0))"
}
mgr_cert(){
 local ac="$HOME/.acme.sh/acme.sh" ans
 if [[ -s "$CERT" ]]; then openssl x509 -in "$CERT" -noout -subject -issuer -dates; openssl x509 -in "$CERT" -noout -checkend 2592000 >/dev/null && echo "证书有效期超过 30 天" || echo "证书将在 30 天内到期或已过期"; else echo "证书不存在"; fi
 if [[ -x "$ac" ]]; then "$ac" --list || true; crontab -l 2>/dev/null|grep -F acme.sh || echo "未发现 acme.sh cron"; read -rp "执行一次续期检查？[y/N] " ans; [[ "$ans" == [yY] ]] && "$ac" --cron --home "$HOME/.acme.sh"; else echo "未找到 acme.sh"; fi
}
mgr_backup(){
 local f stamp p; mkdir -p "$MGR_BACKUPS"; chmod 700 "$MGR_BACKUPS"
 [[ -s "$CONF" && -s "$STATE_FILE" ]] || { echo "配置文件缺失"; return 1; }
 stamp=$(date +%Y%m%d-%H%M%S); f="$MGR_BACKUPS/xray-dual-$stamp.tar.gz"
 local -a paths=(usr/local/etc/xray/config.json etc/xray-dual-protocol/state.json etc/nginx/conf.d/xray-dual.conf ssl/xray.crt ssl/xray.key etc/systemd/system/xray.service.d/dual-protocol.conf usr/local/sbin/xray-dual-cert-reload); local -a keep=()
 for p in "${paths[@]}"; do [[ -f "/$p" ]] && keep+=("$p"); done
 tar -C / -czf "$f" "${keep[@]}" || { rm -f "$f"; return 1; }
 chmod 600 "$f"; sha256sum "$f" >"$f.sha256"; chmod 600 "$f.sha256"
 echo "备份完成：$f"; echo "备份包含密钥和 UUID，请妥善保管"
}
mgr_restore_files(){
 local d="$1" p
 [[ -s "$d/usr/local/etc/xray/config.json" && -s "$d/etc/xray-dual-protocol/state.json" ]] || return 1
 install -D -m 600 "$d/usr/local/etc/xray/config.json" "$CONF"; secure_xray_config || return 1; install -D -m 600 "$d/etc/xray-dual-protocol/state.json" "$STATE_FILE"
 for p in etc/nginx/conf.d/xray-dual.conf ssl/xray.crt ssl/xray.key etc/systemd/system/xray.service.d/dual-protocol.conf usr/local/sbin/xray-dual-cert-reload; do if [[ -f "$d/$p" ]]; then install -D -m 600 "$d/$p" "/$p"; else rm -f "/$p"; fi; done
}
mgr_restore(){
 local -a files=(); local f n=0 choice selected tmp old p
 mkdir -p "$MGR_BACKUPS"
 while IFS= read -r f; do files+=("$f"); done < <(find "$MGR_BACKUPS" -maxdepth 1 -type f -name 'xray-dual-*.tar.gz'|sort -r)
 ((${#files[@]})) || { echo "没有备份"; return 1; }
 for f in "${files[@]}"; do ((n+=1)); echo "$n. $(basename "$f")"; done
 read -rp "选择备份（0 返回）: " choice; [[ "$choice" == 0 ]] && return
 [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>0 && choice<=${#files[@]})) || { echo "编号无效"; return 1; }
 selected="${files[$((choice-1))]}"
 read -rp "恢复将覆盖当前项目配置，是否继续？[y/N] " confirm
 [[ "$confirm" == [yY] ]] || return 0
 echo "[安全] 先自动备份当前配置，再执行恢复"
 mgr_backup || { echo "恢复前自动备份失败，取消恢复"; return 1; }
 (cd "$MGR_BACKUPS" && sha256sum -c "$(basename "$selected").sha256") || return 1
 while IFS= read -r p; do case "$p" in usr/local/etc/xray/config.json|etc/xray-dual-protocol/state.json|etc/nginx/conf.d/xray-dual.conf|ssl/xray.crt|ssl/xray.key|etc/systemd/system/xray.service.d/dual-protocol.conf|usr/local/sbin/xray-dual-cert-reload) ;; *) echo "备份含非预期路径 $p"; return 1;; esac; done < <(tar -tzf "$selected") || return 1
 tmp=$(mktemp -d); old=$(mktemp -d); tar -xzf "$selected" -C "$tmp" || { rm -rf "$tmp" "$old"; return 1; }
 for p in usr/local/etc/xray/config.json etc/xray-dual-protocol/state.json etc/nginx/conf.d/xray-dual.conf ssl/xray.crt ssl/xray.key etc/systemd/system/xray.service.d/dual-protocol.conf usr/local/sbin/xray-dual-cert-reload; do [[ -f "/$p" ]] && install -D -m 600 "/$p" "$old/$p"; done
 if ! mgr_restore_files "$tmp" || ! jq -e '.inbounds|type=="object"' "$STATE_FILE" >/dev/null || ! xray_test >/dev/null 2>&1 || ! nginx -t >/dev/null 2>&1; then mgr_restore_files "$old" || true; rm -rf "$tmp" "$old"; echo "恢复校验失败，已尝试回滚"; return 1; fi
 systemctl daemon-reload
 if ! systemctl restart xray || ! systemctl is-active --quiet xray || { systemctl is-active --quiet nginx && ! systemctl reload nginx; }; then mgr_restore_files "$old" || true; systemctl daemon-reload; xray_test >/dev/null 2>&1 && systemctl restart xray >/dev/null 2>&1 || true; nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true; rm -rf "$tmp" "$old"; echo "服务恢复失败，已尝试回滚"; return 1; fi
 rm -rf "$tmp" "$old"; echo "备份恢复完成"
}
mgr_modify(){
 mgr_select || return
 has "$MGR_TAG" || { echo "配置未安装"; return 1; }
 jq -e --arg t "$MGR_TAG" '.inbounds[]?|select(.tag==$t)' "$CONF" >/dev/null || { echo "状态与 Xray 入站不一致，拒绝修改"; return 1; }
 echo "修改 $MGR_NAME"
 echo "1. 重新生成 UUID"
 [[ "$MGR_TAG" == xhttp-nginx ]] || echo "2. 修改监听端口（WS-Nginx 为本机内部端口）"
 case "$MGR_TAG" in ws-nginx|xhttp-reality|xhttp-tls|xhttp-nginx) echo "3. 修改传输路径";; esac
 case "$MGR_TAG" in tcp-reality-vision|xhttp-reality) echo "4. 修改 REALITY dest / SNI"; echo "5. 重新生成 REALITY 密钥和 Short ID";; esac
 read -rp "选择（0 返回）: " choice
 [[ "$choice" == 0 ]] && return
 local tmp st value tag="$MGR_TAG" oldport dest dp sni sid
 tmp=$(mktemp); st=$(mktemp)
 case "$choice" in
  1)
   value=$(new_uuid)
   jq --arg t "$tag" --arg id "$value" '.inbounds|=map(if .tag==$t then .settings.clients[0].id=$id else . end)' "$CONF" >"$tmp"
   jq --arg t "$tag" --arg id "$value" '.inbounds[$t].uuid=$id|.inbounds[$t].link=""' "$STATE_FILE" >"$st"
   ;;
  2)
   [[ "$tag" != xhttp-nginx ]] || { rm -f "$tmp" "$st"; echo "XHTTP-Nginx 使用 Unix Socket，没有 TCP 监听端口"; return 1; }
   oldport=$(jq -r --arg t "$tag" '.inbounds[$t].port // empty' "$STATE_FILE")
   read -rp "新的监听端口: " value
   valid_port "$value" || { rm -f "$tmp" "$st"; echo "端口无效"; return 1; }
   if [[ "$value" != "$oldport" ]] && ss -H -lnt "( sport = :$value )" 2>/dev/null | grep -q .; then rm -f "$tmp" "$st"; echo "端口已占用"; return 1; fi
   jq --arg t "$tag" --argjson p "$value" '.inbounds|=map(if .tag==$t then .port=$p else . end)' "$CONF" >"$tmp"
   jq --arg t "$tag" --argjson p "$value" '.inbounds[$t].port=$p|.inbounds[$t].link=""' "$STATE_FILE" >"$st"
   ;;
  3)
   case "$tag" in ws-nginx|xhttp-reality|xhttp-tls|xhttp-nginx);; *) rm -f "$tmp" "$st"; echo "此传输模式没有可编辑的路径"; return 1;; esac
   read -rp "新的路径（必须以 / 开头）: " value
   [[ "$value" == /* && "$value" != *" "* && "$value" != *"?"* && "$value" != *"#"* ]] || { rm -f "$tmp" "$st"; echo "路径格式无效"; return 1; }
   if jq -e --arg t "$tag" --arg p "$value" '[.inbounds|to_entries[]|select(.key!=$t and .value.path==$p)]|length>0' "$STATE_FILE" >/dev/null; then
     rm -f "$tmp" "$st"; echo "该路径已被其他入站使用，请选择不同路径"; return 1
   fi
   if [[ "$tag" == ws-nginx ]]; then
     jq --arg t "$tag" --arg p "$value" '.inbounds|=map(if .tag==$t then .streamSettings.wsSettings.path=$p else . end)' "$CONF" >"$tmp"
   else
     jq --arg t "$tag" --arg p "$value" '.inbounds|=map(if .tag==$t then .streamSettings.xhttpSettings.path=$p else . end)' "$CONF" >"$tmp"
   fi
   jq --arg t "$tag" --arg p "$value" '.inbounds[$t].path=$p|.inbounds[$t].link=""' "$STATE_FILE" >"$st"
   ;;
  4)
   [[ "$tag" == tcp-reality-vision || "$tag" == xhttp-reality ]] || { rm -f "$tmp" "$st"; echo "此配置不是 REALITY"; return 1; }
   read -rp "新的 REALITY dest 主机名（不含端口）: " dest
   [[ "$dest" =~ ^[A-Za-z0-9.-]+$ && "$dest" != .* && "$dest" != *. && "$dest" != *..* ]] || { rm -f "$tmp" "$st"; echo "dest 格式无效"; return 1; }
   read -rp "dest 端口 [443]: " dp; dp=${dp:-443}; valid_port "$dp" || { rm -f "$tmp" "$st"; echo "dest 端口无效"; return 1; }
   read -rp "SNI [$dest]: " sni; sni=${sni:-$dest}
   [[ "$sni" =~ ^[A-Za-z0-9.-]+$ && "$sni" != .* && "$sni" != *. && "$sni" != *..* ]] || { rm -f "$tmp" "$st"; echo "SNI 格式无效"; return 1; }
   jq --arg t "$tag" --arg d "$dest:$dp" --arg s "$sni" '.inbounds|=map(if .tag==$t then (.streamSettings.realitySettings.dest=$d | .streamSettings.realitySettings.serverNames=[$s]) else . end)' "$CONF" >"$tmp"
   jq --arg t "$tag" --arg d "$dest" --arg s "$sni" --argjson dp "$dp" '.inbounds[$t].dest=$d|.inbounds[$t].dest_port=$dp|.inbounds[$t].sni=$s|.inbounds[$t].link=""' "$STATE_FILE" >"$st"
   ;;
  5)
   [[ "$tag" == tcp-reality-vision || "$tag" == xhttp-reality ]] || { rm -f "$tmp" "$st"; echo "此配置不是 REALITY"; return 1; }
   reality_keys; sid=$(openssl rand -hex 8)
   jq --arg t "$tag" --arg pk "$R_PRIV" --arg sid "$sid" '.inbounds|=map(if .tag==$t then (.streamSettings.realitySettings.privateKey=$pk | .streamSettings.realitySettings.shortIds=[$sid]) else . end)' "$CONF" >"$tmp"
   jq --arg t "$tag" --arg pbk "$R_PUB" --arg sid "$sid" '.inbounds[$t].pbk=$pbk|.inbounds[$t].sid=$sid|.inbounds[$t].link=""' "$STATE_FILE" >"$st"
   ;;
  *) rm -f "$tmp" "$st"; echo "无效选项"; return 1;;
 esac
 if ! jq empty "$tmp" || ! jq -e '.inbounds|type=="object"' "$st" >/dev/null; then rm -f "$tmp" "$st"; echo "候选配置校验失败"; return 1; fi
 manager_txn_snapshot
 if ! apply_config <"$tmp"; then manager_txn_rollback; rm -f "$tmp" "$st"; return 1; fi
 if ! install -m 600 "$st" "$STATE_FILE"; then manager_txn_rollback; rm -f "$tmp" "$st"; return 1; fi
 rm -f "$tmp" "$st"
 if [[ "$tag" == ws-nginx || "$tag" == xhttp-nginx ]]; then
   if ! nginx_aggregate; then manager_txn_rollback; echo "Nginx 路由更新失败，已尝试回滚"; return 1; fi
 fi
 manager_txn_commit
 refresh_saved_links
 echo "[完成] 配置已修改；请重新导入客户端链接"
 make_saved_link "$tag"
}
mgr_remove(){
 mgr_select || return; has "$MGR_TAG" || { echo "配置未安装"; return 1; }
 read -rp "确认卸载 $MGR_NAME？[y/N] " confirm; [[ "$confirm" == [yY] ]] || return
 remove_v2 "$MGR_TAG"
}
menu_v2(){
 local c
 while true; do
  clear 2>/dev/null || true; echo "Xray Dual Protocol OneKey"; echo "版本：$PROJECT_VERSION"; mgr_status
  echo "========== 配置安装 =========="; echo "1. 安装单项配置"; echo "2. 按顺序安装全部七种"
  echo; echo "========== 配置管理 =========="; echo "3. 查看所有配置"; echo "4. 修改已有配置"; echo "5. 卸载单项配置"; echo "6. 输出客户端链接"; echo "7. 显示二维码"
  echo; echo "========== 服务管理 =========="; echo "8. 启动 / 停止 / 重启"; echo "9. 查看运行日志"; echo "10. 配置健康检查"
  echo; echo "========== 证书与备份 =========="; echo "11. 证书状态与续期检查"; echo "12. 备份配置"; echo "13. 恢复配置"; echo; echo "0. 退出"
  read -rp "请选择操作: " c
  case "$c" in 1) mgr_install;; 2) all_v2;; 3) mgr_list;; 4) mgr_modify;; 5) mgr_remove;; 6) mgr_links;; 7) mgr_qr;; 8) mgr_services;; 9) mgr_logs;; 10) mgr_health;; 11) mgr_cert;; 12) mgr_backup;; 13) mgr_restore;; 0) echo "退出管理菜单"; return 0;; *) echo "无效选项";; esac
  echo; read -rp "按回车返回主菜单..." _
 done
}

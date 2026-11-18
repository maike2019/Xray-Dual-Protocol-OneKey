# Xray-Dual-Protocol-OneKey

基于 [wulabing/Xray_onekey](https://github.com/wulabing/Xray_onekey) 衍生的双协议安装管理项目，保留原项目 MIT 版权声明（见 [LICENSE](LICENSE)）。

> **状态：首版开发中。** 文件已提交，但尚未在真实 VPS 完成端到端安装、续期及客户端互通测试。请先在快照/测试机验证。

## 功能目标

- VLESS + TCP + TLS + Nginx + WebSocket：Nginx 443，Xray 回源仅监听 127.0.0.1。
- VLESS + TCP + REALITY + Vision：独立 TCP 端口，默认 8443。
- 两种入站共存；REALITY 支持修改监听端口、dest 域名/端口、serverNames，重新生成密钥和 Short ID。
- 端口占用只报告，不会自动 kill 进程；修改 Xray 配置先备份、测试，失败尝试回滚。
- ACME HTTP-01 challenge location 常驻 Nginx 80 端口；统一续期 hook 处理权限、配置测试和服务重载。

## 安装

建议全新 Debian 12/13 或 Ubuntu 22.04/24.04，root 执行。WS TLS 需要域名正确解析至 VPS，并允许公网 TCP 80/443；REALITY 默认 TCP 8443 需在云安全组及系统防火墙放行。

```bash
wget -O install.sh https://raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh
chmod +x install.sh
bash install.sh
```

安装菜单可选仅 WS、仅 REALITY 或两者。注意：脚本不会自动关闭防火墙，也不会清理端口占用进程。

## 证书续期 Bug：原问题与修复方法

### 原 nginx_forward 分支的问题

1. **HTTP-01 路径没有常驻放行。** 原 80 端口常态配置把请求直接 301 到 HTTPS，ACME webroot 验证依赖 CA 跟随重定向，行为不稳健。
2. **重复传入 `--reloadcmd`。** 原 `--installcert` 同一命令分别传入重启 Xray、Nginx 的两个 reloadcmd，不是可靠的多动作编排方式，存在后一个覆盖前一个的风险。
3. **证书权限写死。** 原脚本使用 `chown -R nobody.$cert_group /ssl/*`，没有可靠读取 systemd 中 Xray 的实际运行用户，且点号属主语法和目录自身权限处理不够稳妥。
4. **手动 cron 不等于自动续期链路正确。** 手动运行 `acme.sh --cron` 后重启服务，不能证明 cron 定时任务、证书部署路径和续期 hook 均正确。
5. **临时改写 Nginx 配置易受端口/行号影响。** challenge 放行不应依赖临时按行号 sed 修改配置。

### 本项目修复逻辑

- 80 端口始终配置 `location ^~ /.well-known/acme-challenge/`，固定使用 webroot；其他路径再重定向/拒绝。
- 证书申请与续期使用相同 webroot，和 TLS 对外监听端口解耦。
- `--install-cert` 只注册一个统一 reload hook，避免重复传递 `--reloadcmd`。
- hook 读取 `systemctl show xray -p User`，确定 Xray 运行用户；设置证书属主和权限后，依次执行 `nginx -t`、`xray run -test`，通过后 reload Nginx 并重启 Xray。
- 安装时调用 `acme.sh --install-cronjob`，菜单提供 cron/timer、证书到期时间和 acme.sh 证书列表检查。
- 不宣称“手动续期成功”等于自动续期已验证。自动续期仍依赖 cron 服务、DNS、TCP 80 入站和 CA 可达性。

建议部署后检查：

```bash
/root/.acme.sh/acme.sh --cron --home /root/.acme.sh --debug
openssl x509 -in /ssl/xray.crt -noout -dates
nginx -t
xray run -test -config /usr/local/etc/xray/config.json
```

## 已知限制

- 首版只支持 Debian/Ubuntu；不自动关闭 UFW/nftables/firewalld。
- 首版 REALITY SNI 交互设置为单项；配置本身使用数组，可后续扩展多 SNI 管理。
- 首版菜单尚未实现 WS 的所有交互修改项；可查看当前 Xray 配置文件。
- 尚未进行 VPS 实机测试。不同 Xray-core 版本的 `xray x25519` 输出格式可能不同；脚本遇到无法解析会停止。
- Xray WebSocket transport 已被标记 deprecated，未来可能移除；Nginx 前置 TLS 结构也可能遭遇针对性阻断。

## 许可

MIT License。保留原作者声明：Copyright (c) 2022 wulabing。本衍生项目不代表原作者背书。

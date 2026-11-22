## Configuration rollback protection (2.0.5-dev)

Xray configuration changes are backed up before activation. If Xray validation, restart, or active-state checks fail, the previous configuration is restored and the old service is restarted when possible. Failed Nginx aggregate validation or reload also triggers restoration of the previous project configuration. These recovery paths still require fault-injection testing on a disposable VPS.

## Installation flow (2.0.4-dev)

- The menu shows the registered state of all seven inbound modes before installation.
- “Install all seven” processes configurations sequentially. The next mode starts only after the current mode passes Xray configuration and service checks.
- Nginx-fronted WS/XHTTP modes also require a valid Nginx configuration and active Nginx service.
- Installation logs stream while each mode is running. Successful client links are saved and all saved links are printed together at the end; a failure stops subsequent installation and prints the partial result.
- These checks validate server-side configuration and service state; client connectivity still needs to be tested from a client application.

# Xray-Dual-Protocol-OneKey

一个基于 [wulabing/Xray_onekey](https://github.com/wulabing/Xray_onekey) 衍生的多入站安装与管理项目，支持七种 VLESS 传输/安全组合，可在同一台 VPS 上独立安装并共存。

> **状态：早期开发版。** 首版脚本和文档已提交，但尚未完成真实 VPS 的完整安装、自动续期、升级回滚及客户端互通验收。请先在测试机验证，不要直接覆盖生产节点。

## 功能

- VLESS + TCP + TLS + Nginx + WebSocket。
- VLESS + TCP + REALITY + Vision。
- VLESS + TCP + TLS + Vision。
- VLESS + TCP + TLS（不启用 Vision）。
- VLESS + XHTTP + REALITY（不启用 Vision）。
- VLESS + XHTTP + TLS。
- VLESS + XHTTP + TLS + Nginx（Unix Socket 前后端分离）。
- 七种入站使用独立 tag、UUID、监听端口/路径，可在同一台 VPS 上共存。
- WS-Nginx 与 XHTTP-Nginx 共用 Nginx TCP/443，通过不同 URL path 分流；安装/卸载其中一种会保留另一种路由。
- 提供逐项安装、七项批量安装、查看配置、逐项卸载和分享链接输出。
- TLS 入站共用一个项目域名和 ACME 证书；续期使用统一 hook。
- 端口占用只报告，不自动 kill 进程；更新 Xray 配置前备份并执行配置测试。

## 环境要求

### 支持的系统

当前首版脚本仅明确支持 Debian/Ubuntu（使用 apt 和 systemd）：

| 发行版 | 版本 | 状态 |
| --- | --- | --- |
| Debian | 12 / 13 | 目标测试环境 |
| Ubuntu | 22.04 / 24.04 | 目标测试环境 |
| 其他 Debian/Ubuntu | 未验证 | 可能有软件包或服务差异 |
| Rocky / AlmaLinux / CentOS | 暂不支持 | 当前脚本不支持 yum/dnf |

### 准备工作

- 一台可使用 root 登录的 Debian/Ubuntu VPS，建议全新系统。
- 安装前备份已有 Xray、Nginx、证书和防火墙配置。
- WS TLS 需要域名 A/AAAA 记录指向 VPS，公网 TCP 80、443 可访问。
- REALITY 需要选择有效的 dest 域名及端口；默认监听 TCP 8443。
- 在云厂商安全组和系统防火墙中放行实际使用的 TCP 端口。
- 保证系统时间和 DNS 正常，并具备基本 Linux 命令行知识。

## 快速开始

确保 VPS 满足上方环境要求，并以 root 用户登录。安装脚本提供七种配置的独立安装、批量安装、查看和逐项卸载。选择“安装全部七种配置”时，脚本会依次询问域名、REALITY dest/SNI 等必要参数；TLS 相关配置共用同一域名证书。

## 安装/更新方式

本项目通过同一个安装脚本管理以下七种配置：

1. VLESS + TCP + TLS + Nginx + WebSocket（Nginx 前置）。
2. VLESS + TCP + REALITY + Vision（Xray 直连）。
3. VLESS + TCP + TLS + Vision（Xray 直连）。
4. VLESS + TCP + TLS（Xray 直连，不配置 flow）。
5. VLESS + XHTTP + REALITY（Xray 直连，不配置 Vision flow）。
6. VLESS + XHTTP + TLS（Xray 直连）。
7. VLESS + XHTTP + TLS + Nginx（Nginx 前置，Xray 通过 Unix Socket 接收转发）。

第 1、7 项共用 Nginx 的 TCP/443，使用不同路径；其余五项使用独立 Xray 监听端口。所有 TLS 入站共用首次设置的域名和证书。默认端口仅作为建议值，脚本会检查端口占用。

当前七合一开发版位于 `feature/seven-inbound-modes` 分支。请使用下面这个分支专用下载地址；不要把 URL 中的分支改成 `main`，否则会下载到旧版 1.x。以 root 用户执行：

```bash
wget -N -O install.sh "https://raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/feature/seven-inbound-modes/install.sh" && chmod +x install.sh && bash install.sh
```

更新前请备份 `/usr/local/etc/xray/config.json`、`/etc/nginx`、`/ssl` 和 `/etc/xray-dual-protocol`。2.x 使用新的 JSON 状态登记文件；检测到 1.x 的 `dual-ws`/`dual-reality` 旧入站而没有新状态文件时，会拒绝继续，以免覆盖旧配置。1.x 到 2.x 尚不提供自动迁移，请先阅读 [迁移说明](docs/MIGRATION_v1_to_v2.md)。

## REALITY 参数说明

- TCP REALITY + Vision 默认本机监听端口为 `8443`；XHTTP + REALITY 默认本机监听端口为 `8446`。这是客户端连接 VPS 时使用的端口。
- `dest` 只填写目标主机名，不要带端口，例如 `www.calstatela.edu`。下一步单独询问目标端口，默认 `443`，两项组合后才是 `www.calstatela.edu:443`。
- `SNI` 只填写主机名，默认沿用 dest；通常应与目标站点证书接受的名称相符。
- REALITY 参数输入示例（按提示逐项输入）：

  ```text
  本机监听端口 [8443]（客户端连接 VPS 时使用的端口）: [回车，采用 8443]
  REALITY dest 主机名（只填域名/IP，不含端口）: www.calstatela.edu
  dest 端口 [443]（目标网站端口，通常为 443）: [回车，采用 443]
  SNI [www.calstatela.edu]（留空则使用 dest 主机名）: [回车，采用默认值]
  ```

  因此本例对应：VPS 监听端口 `8443`，REALITY target/dest 为 `www.calstatela.edu:443`，SNI 为 `www.calstatela.edu`。不要把 `:8443` 追加到 dest。
- Private Key 只保存在服务端；Xray 26.x 输出的 `Password (PublicKey)` 是客户端使用的公钥，不能与 Private Key 混淆。
- REALITY target 的 TLS/ALPN 特征只是筛选条件之一；优先核对目标 IP/ASN 与站点证书。避免把 Cloudflare 等大型 CDN 的前端 IP 当作首选 target，因为未通过 REALITY 认证的流量会回落转发到 target。
- 只有 TCP + REALITY + Vision 使用 `xtls-rprx-vision`；XHTTP + REALITY 不配置 Vision flow。

重新生成密钥或 Short ID 后，旧客户端链接会失效，必须同步更新客户端。

## 导入链接规范

参考 [XTLS/Xray-core 分享链接讨论](https://github.com/XTLS/Xray-core/issues/91) 和 [Xray-core](https://github.com/XTLS/Xray-core)。

WS TLS 链接包含 UUID、地址、端口、`security=tls`、`type=ws`、`host` 和 URL 编码的 `path`。XHTTP 链接包含 `type=xhttp`、路径和对应 mode。TCP REALITY + Vision 链接包含 `flow=xtls-rprx-vision`；XHTTP + REALITY 不包含 flow。所有 REALITY 链接包含 `security=reality`、`sni`、`fp`、`pbk` 和 `sid`。

导入失败时核对客户端版本、UUID、端口、SNI、公钥和 Short ID。切勿把 REALITY Private Key 分享给客户端。

## 注意事项

- 不理解参数时先使用默认值；REALITY 的 dest 与 SNI 不是同一项。
- 端口占用时脚本只报告，不会结束进程；请识别占用者，避免误停 SSH/Nginx。
- 脚本不会自动关闭 UFW/nftables，也不会替你配置云安全组。
- Nginx 前置 WS/XHTTP 需要 TCP 80/443；直连 TLS 和 REALITY 需要开放各自的 Xray 监听端口。
- 七种配置可以共存，但实际并发能力、网络质量和客户端兼容性仍需在目标 VPS/客户端上测试。
- TLS 入站共用首次设置的单一域名证书；当前版本不支持多个域名/独立证书映射。
- XHTTP + Nginx 使用 Nginx `grpc_pass` 到 Unix Socket，依赖 systemd 的 `www-data` 组和 0660 socket 权限。
- 自动续期依赖 acme.sh 定时任务、DNS、HTTP-01 的 TCP 80 可达性和 CA 可达性；安装成功不等于自动续期已实测。
- WebSocket transport 已被 Xray 标记为弃用，未来可能移除；项目保留 WS 是为兼容既有客户端/部署。
- XHTTP + Nginx 当前以 HTTP/2 为基线，不自动配置 HTTP/3/QUIC；发行版 Nginx 的 HTTP/3 能力并不一致。
- 当前支持逐项安装/卸载，不是完整的配置编辑器；修改参数建议先卸载对应项再重新安装。
- 当前属于开发版；静态检查不等于真实 VPS 安装、续期和客户端互通验收。

## 修复说明

### 原 nginx_forward 分支发现的问题

1. **HTTP-01 challenge location 未常驻。** 常态 Nginx 80 端口配置把请求重定向到 HTTPS，未稳定保留独立的 `/.well-known/acme-challenge/` webroot 路径，续期依赖 CA 对重定向的处理。
2. **重复传入 `--reloadcmd`。** 原 `acme.sh --install-cert` 命令重复传递 reloadcmd，分别重启 Xray 和 Nginx；这不是可靠的组合 hook 编排方式。
3. **证书权限处理不可靠。** 原逻辑使用硬编码 nobody 和递归 chown，没有可靠读取 Xray systemd 实际运行用户，也没有妥善处理 `/ssl` 目录自身权限。
4. **手动 cron 不等于自动续期正常。** 手动执行 `acme.sh --cron` 不能证明系统定时任务存在、启用且会正常触发。
5. **临时改写 Nginx 配置脆弱。** 依赖按行号 sed 或临时改写配置放行 challenge，容易受配置变化影响。

### 本项目修复方法

- Nginx 80 端口常驻 `location ^~ /.well-known/acme-challenge/`，统一使用固定 webroot。
- 签发和续期使用同一个 webroot，验证路径不依赖 TLS 对外端口。
- `--install-cert` 仅注册一个组合 reload hook。
- hook 读取 `systemctl show xray -p User`，设置证书属主/权限后执行 `nginx -t` 和 `xray run -test`，通过后重载 Nginx、重启 Xray。
- 安装时调用 `acme.sh --install-cronjob`，并提供证书列表、到期时间和 cron/timer 检查。
- 区分手动续期测试与自动续期验收；后者仍需在 VPS 上验证 DNS、TCP 80、cron 和 hook 日志。

部署后可检查：

```bash
/root/.acme.sh/acme.sh --list
crontab -l
openssl x509 -in /ssl/xray.crt -noout -dates
nginx -t
xray run -test -config /usr/local/etc/xray/config.json
```

上述为代码中的修复设计，不代表已完成真实 VPS 自动续期验收。

## 启动方式

```bash
systemctl start xray       # 启动 Xray
systemctl stop xray        # 停止 Xray
systemctl restart xray     # 重启 Xray
systemctl status xray      # 查看状态
journalctl -u xray -e      # 查看日志

systemctl start nginx      # 启动 Nginx
systemctl stop nginx       # 停止 Nginx
nginx -t                   # 检查 Nginx 配置
```

## 相关目录

| 路径 | 说明 |
| --- | --- |
| `/usr/local/etc/xray/config.json` | Xray 主配置 |
| `/etc/nginx/` | Nginx 配置目录 |
| `/etc/nginx/conf.d/xray-dual.conf` | 项目生成的站点配置 |
| `/var/www/xray-acme/` | ACME HTTP-01 webroot |
| `/ssl/xray.key` | TLS 私钥 |
| `/ssl/xray.crt` | TLS fullchain 证书 |
| `/etc/xray-dual-protocol/state.json` | 项目入站登记、共享域名和路径记录 |
| `/usr/local/sbin/xray-dual-cert-reload` | 证书续期 hook |
| `/run/xray-dual/xhttp.sock` | XHTTP + Nginx 的 Unix Socket（仅安装第 7 项时创建） |
| `/usr/local/share/xray/geoip.dat` | 可选 GeoIP 数据文件 |
| `/usr/local/share/xray/geosite.dat` | 可选 GeoSite 数据文件 |

说明：geoip.dat 和 geosite.dat 是数据文件，不是目录。首版脚本尚未自动下载/更新它们；若手动放置，请确保 Xray 配置引用路径一致。

## 鸣谢

- [wulabing/Xray_onekey](https://github.com/wulabing/Xray_onekey)：原始项目及作者，保留原项目 MIT 版权声明。
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [acme.sh](https://github.com/acmesh-official/acme.sh)
- [Nginx](https://nginx.org/)
- 感谢所有上游项目贡献者和测试反馈者。

## 许可证

遵循 MIT License。原项目版权声明保留于 [LICENSE](LICENSE)。本衍生项目不代表上游作者背书。

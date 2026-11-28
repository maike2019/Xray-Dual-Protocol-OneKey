## 版本更新摘要

### 多用户与订阅规划（设计阶段，尚未启用）

已确认下一阶段目标：多用户管理、每用户独立订阅，以及管理员总订阅。订阅服务计划完全自建于 VPS，不依赖第三方订阅转换网站；用户可分配七种入站的任意子集，用户停用/删除时撤销 UUID 和订阅令牌。数据迁移、令牌隔离、Nginx 日志脱敏、事务回滚和 V2RayN 实机导入均须完成测试后，才会开放该功能。详细设计见 [多用户与双层订阅设计](docs/USER_SUBSCRIPTION_DESIGN.md)。


### 2.1.0-dev：交互式管理面板与运维功能

- 新增持续运行的 13 项主菜单：单项/批量安装、配置查看/修改/卸载、客户端链接/二维码、服务控制、日志、健康检查、证书续期检查、备份与恢复。
- 新增独立管理模块 `lib/management.sh`；安装脚本从当前开发分支下载并加载该模块。
- 配置编辑支持重新生成 UUID、修改 TCP 监听端口（WS-Nginx 修改内部端口）、修改 WS/XHTTP 路径，以及修改 REALITY dest/SNI、重新生成 REALITY 密钥和 Short ID。
- WS-Nginx、XHTTP-Nginx 的路径变更会同步更新 Nginx 聚合路由；Xray 入站、状态文件、Nginx 路由及 XHTTP systemd drop-in 增加跨组件回滚保护。
- 直连入站新增 Xray 配置与状态文件事务保护；状态文件写入改为临时文件校验后原子替换。
- 新增备份 SHA256 校验、恢复前快照、Xray/Nginx 配置校验和恢复失败回滚尝试。
- **功能边界：**证书续期检查依赖 root 用户下的 acme.sh；恢复仅处理项目管理的配置文件。真实 VPS 故障注入、续期和客户端互通仍需实测。

### 2.0.5-dev：配置变更失败回滚保护

- 修改 Xray 配置前先备份原配置。
- 新配置需通过 JSON 格式和 Xray 配置测试后才会应用。
- 如果配置测试、Xray 重启或服务运行状态检查失败，脚本会恢复原配置，并尝试重新启动旧服务。
- Nginx 聚合配置测试或重载失败时，会恢复之前的项目配置，并尝试重新加载旧配置。
- **验证边界：**上述回滚逻辑仍需在隔离测试 VPS 上进行故障注入验证；静态检查不能代替真实服务恢复测试。

### 2.0.4-dev：安装进度、状态识别与链接汇总

- 主菜单顶部显示七种入站配置的登记和运行状态。
- 选择“按顺序安装全部七种”后，脚本按 1/7 至 7/7 逐项安装；当前项目通过基础检查后才会继续下一项。
- 每项安装后检查 Xray 配置和服务状态；WS+Nginx、XHTTP+Nginx 还会检查 Nginx 配置和服务状态。
- 安装日志实时显示，成功生成的客户端链接会保存，并在流程结束时统一汇总。
- 任一项目失败时停止后续安装，同时显示已完成项目、当前状态和已保存的链接。
- **验证边界：**这些检查属于服务端基础验收，不代表客户端已经成功连接；仍需在客户端导入链接并进行实际连通测试。
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

## 当前脚本菜单结构（2.1.0-dev）

以下为当前开发分支的实际菜单。主菜单保持循环运行，完成操作后按回车返回。

```text
Xray Dual Protocol OneKey
版本：2.1.0-dev

========== 服务状态 ==========
Xray       : 运行正常 / 未运行
Nginx      : 运行正常 / 未运行
TLS 证书   : 有效 / 未安装或无效
已安装配置 : N / 7

========== 配置安装 ==========
1. 安装单项配置
2. 按顺序安装全部七种

========== 配置管理 ==========
3. 查看所有配置
4. 修改已有配置
5. 卸载单项配置
6. 输出客户端链接
7. 显示二维码

========== 服务管理 ==========
8. 启动 / 停止 / 重启
9. 查看运行日志
10. 配置健康检查

========== 证书与备份 ==========
11. 证书状态与续期检查
12. 备份配置
13. 恢复配置

0. 退出
```

### 配置修改范围

- 所有模式：重新生成 UUID。
- TCP 直连模式：修改监听端口。
- WS-Nginx：修改本机内部监听端口及 WS 路径。
- XHTTP 直连、XHTTP-Nginx：修改 XHTTP 路径。
- 两种 REALITY 直连模式：修改 dest 主机名/端口、SNI，或重新生成 REALITY 密钥和 Short ID。
- Nginx 前置模式的路径修改会重新生成聚合 Nginx 配置，保留另一个已安装模式的路由。
- 目前不提供 TLS 域名迁移、证书私钥轮换、XHTTP-Nginx Socket 路径变更等高级编辑入口；此类变更应在备份后按维护流程操作。

### 备份与恢复范围

备份包括 Xray 主配置、项目状态文件、项目 Nginx 配置、TLS 证书/私钥、项目 systemd drop-in 和证书 reload hook。备份文件设置为仅 root 可读写，并生成 SHA256 校验文件。恢复前会保存当前文件快照，并校验 Xray JSON、Xray 配置和 Nginx 配置；恢复失败时尝试回滚。

**重要：**备份包含 REALITY 私钥、TLS 私钥、UUID 和客户端链接。请勿公开上传。当前恢复功能仅覆盖上述项目文件，不会恢复整个操作系统、防火墙规则、云安全组或 acme.sh 账户目录。

### 验证边界

GitHub Actions 的 Bash 语法和静态检查只能证明脚本语法及部分结构检查通过，不等同于真实 VPS 的安装、服务恢复、自动续期或客户端互通验收。尤其是恢复回滚和多入站并存，仍需在隔离 VPS 上进行故障注入和客户端测试。
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

# Xray-Dual-Protocol-OneKey

一个基于 [wulabing/Xray_onekey](https://github.com/wulabing/Xray_onekey) 衍生的双协议安装与管理项目：保留 Nginx 前置 VLESS WebSocket TLS，并增加独立 VLESS REALITY + Vision 入站。

> **状态：早期开发版。** 首版脚本和文档已提交，但尚未完成真实 VPS 的完整安装、自动续期、升级回滚及客户端互通验收。请先在测试机验证，不要直接覆盖生产节点。

## 功能

- VLESS + TCP + TLS + Nginx + WebSocket：Nginx 对外监听 443，Xray 回源监听本机端口。
- VLESS + TCP + REALITY + Vision：Xray 直接监听，默认 TCP 8443。
- 两种入站可共存，具备独立 tag 和参数。
- REALITY 基础管理：修改监听端口、dest、SNI，重新生成密钥和 Short ID。
- 安装后输出 VLESS 分享链接。
- ACME HTTP-01 固定 webroot、统一续期 hook、证书权限处理。
- 端口占用只报告，不自动 kill 进程；修改配置前备份并执行 Xray 测试。

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

确保 VPS 满足上方环境要求，并以 root 用户登录。安装和更新统一使用下方的安装命令；脚本会提供交互菜单，可配置 Nginx 前置的 VLESS WebSocket TLS、VLESS REALITY + Vision，或按菜单选择组合部署。

## 安装/更新方式

本项目通过同一个安装脚本管理两种协议：

- VLESS + TCP + TLS + Nginx 前置 + WebSocket：Nginx 对外监听 443，Xray 在本机端口提供 WebSocket 服务。
- VLESS + TCP + REALITY + Vision：Xray 直接监听，默认端口为 TCP 8443。

以 root 用户执行以下命令：

```bash
wget -N -O install.sh "https://raw.githubusercontent.com/maike2019/Xray-Dual-Protocol-OneKey/main/install.sh" && chmod +x install.sh && bash install.sh
```

更新前请备份 `/usr/local/etc/xray/config.json`、`/etc/nginx` 和 `/ssl`。当前首版尚不是完整的原地升级迁移工具；请先阅读脚本菜单和提示，不要将重复运行安装脚本视为无风险升级。

## REALITY 参数说明

- 监听端口默认 `8443`。
- `dest` 是服务端握手目标，格式为域名和端口，例如 `www.example.com:443`。
- `serverNames` 是允许的 SNI 名称；首版交互支持单项输入。
- Private Key 只保存在服务端；Public Key 和 Short ID 供客户端使用。
- 客户端 flow 为 `xtls-rprx-vision`。

重新生成密钥或 Short ID 后，旧客户端链接会失效，必须同步更新客户端。

## 导入链接规范

参考 [XTLS/Xray-core 分享链接讨论](https://github.com/XTLS/Xray-core/issues/91) 和 [Xray-core](https://github.com/XTLS/Xray-core)。

WS TLS 链接包含 UUID、地址、端口、`encryption=none`、`security=tls`、`type=ws`、`host` 和 URL 编码的 `path`。REALITY 链接包含 UUID、地址、端口、`flow=xtls-rprx-vision`、`security=reality`、`sni`、`fp`、`pbk`、`sid` 和 `type=tcp`。

导入失败时核对客户端版本、UUID、端口、SNI、公钥和 Short ID。切勿把 REALITY Private Key 分享给客户端。

## 注意事项

- 不理解参数时先使用默认值；REALITY 的 dest 与 SNI 不是同一项。
- 端口占用时脚本只报告，不会结束进程；请识别占用者，避免误停 SSH/Nginx。
- 脚本不会自动关闭 UFW/nftables，也不会替你配置云安全组。
- WS TLS 需要 TCP 80/443；REALITY 需要开放所选监听端口。
- 自动续期依赖 acme.sh 定时任务、DNS、80 端口和 CA 可达性；安装成功不等于自动续期已实测。
- WebSocket transport 已被 Xray 标记为弃用，未来可能移除；Nginx 前置 TLS 也可能被针对性阻断。

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
| `/etc/xray-dual-protocol/` | 项目状态记录 |
| `/usr/local/sbin/xray-dual-cert-reload` | 证书续期 hook |
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

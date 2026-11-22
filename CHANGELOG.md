# Changelog

## [2.0.2-dev] - 2026-11-22 — REALITY 密钥解析与输入提示修复

### Fixed
- `xray x25519` 解析同时兼容旧版 `Private key / Public key` 和新版 `PrivateKey / Password` 输出标签。
- REALITY dest 提示明确要求只填写主机名，不包含端口；目标端口单独输入，默认 443。
- 本机 REALITY 监听端口提示明确说明它是客户端连接 VPS 时使用的端口。
- 对 dest、目标端口和 SNI 增加输入校验；格式错误时给出针对性说明。
- README 增加完整输入示例，解释本机监听端口与 dest 目标端口的区别。

### Validation
- 静态检查增加两种 Xray 密钥输出格式的解析测试。
- GitHub Actions 验证 Bash 语法和项目静态检查；实际服务器端连接仍需 VPS 测试。

## [2.0.1-dev] - 2026-11-22 — Nginx 端口识别与分支安装修复

### Fixed
- 移除七合一脚本中遗留的 v1.0.0 菜单与 WS 安装函数，避免执行旧版 TCP/80 端口检查。
- 不再在依赖安装阶段无条件启动 Nginx；需要 ACME HTTP-01 时才检查并启动 Nginx。
- TCP/80 已由 Nginx 监听时允许继续；若由其他进程占用则显示监听信息并安全退出，不结束任何进程。
- TCP/443 检查区分 Nginx 与其他服务，避免误把 Nginx 自身视为冲突。
- README 安装命令改为显式下载 `feature/seven-inbound-modes`，防止从 `main` 获取旧版脚本。

### Validation
- GitHub Actions Bash 语法检查及项目静态检查通过。
- 尚未完成目标 VPS 的实际签发、Nginx 转发和客户端互通测试。

## [2.0.0-dev] - 2026-11-21 — 七种入站开发版

### Added
- 增加 TCP TLS Vision、TCP TLS、XHTTP REALITY、XHTTP TLS、XHTTP TLS + Nginx，形成七种 VLESS 入站模式。
- WS 与 XHTTP 的 Nginx 前置模式聚合到同一个 443 server block，以独立路径分流。
- 增加逐项安装、七项批量安装、查看和逐项卸载。
- XHTTP + Nginx 使用 Unix Socket 和受限 socket 权限；TLS 入站共用项目域名证书。

### Safety / limitations
- 1.x 到 2.x 暂不自动迁移；检测到旧版 tag 时停止，避免覆盖旧配置。
- 目前仅完成代码与静态检查设计，真实 VPS 安装、续期、socket 权限及客户端互通仍需实测。


本文件记录版本变化。每个正式版本发布时，应同步创建 GitHub Release，并将该版本条目作为 Release notes。

## [1.0.0] - 2026-11-18 — 初始开发版本

### Added
- 双协议首版：VLESS + WebSocket + TLS + Nginx，以及 VLESS + REALITY + Vision。
- REALITY 默认监听端口 8443，提供 dest、SNI、端口和密钥参数的基础管理。
- 补齐中文使用文档：准备工作、环境要求、安装/更新方式、导入链接规范、注意事项、修复说明、启动方式、相关目录、鸣谢和功能。
- 增加 geoip.dat / geosite.dat 的可选路径说明。

### Fixed
- Nginx 常驻 ACME HTTP-01 challenge webroot location。
- acme.sh 证书部署使用单一组合 reload hook。
- 续期 hook 处理证书属主/权限，并在重载前测试 Nginx 与 Xray 配置。
- 端口占用时只报告，不自动结束进程。

### Known limitations
- 当前是早期开发版本，尚未完成真实 VPS 安装、自动续期和客户端互通验收。
- 当前仅明确支持 Debian/Ubuntu。
- 独立的 Xray 前置 TLS/回落模式尚未实现。
- geoip.dat/geosite.dat 暂不由安装脚本自动下载或更新。

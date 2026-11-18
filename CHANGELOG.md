# Changelog

本文件记录 Xray-Dual-Protocol-OneKey 的版本变化。正式版发布时，同步创建 GitHub Release，并将对应条目复制到 Release notes。

## [1.0.0] - 2026-11-18 - 初始开发版本

### Added
- 双协议项目首版：VLESS + WebSocket + TLS + Nginx，以及 VLESS + REALITY + Vision。
- REALITY 默认监听端口 8443。
- REALITY dest、SNI、端口及密钥/Short ID 基础管理入口。
- 证书续期问题分析与修复设计文档。
- 安装脚本基础静态检查与 GitHub Actions 工作流。

### Fixed
- 为 ACME HTTP-01 challenge 固定配置 webroot location。
- 将证书部署 reloadcmd 合并为单一 hook。
- 续期 hook 根据 Xray systemd 用户设置证书权限，并在重载前执行 Nginx/Xray 配置测试。
- 不再因端口占用自动 kill 进程。

### Known limitations
- 尚未完成真实 VPS 安装、自动续期和客户端互通验收。
- 当前只明确支持 Debian/Ubuntu 系列。
- Xray 前置 TLS/回落模式未实现；当前协议组合为 Nginx 前置 WS TLS 与 Xray 直连 REALITY。
- geoip.dat/geosite.dat 尚未由安装脚本自动下载或更新。

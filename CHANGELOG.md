# Changelog

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

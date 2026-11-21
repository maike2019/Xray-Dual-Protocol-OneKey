# Changelog

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

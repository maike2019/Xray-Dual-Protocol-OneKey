# v1.0.0 — 初始开发版本

发布日期：2026-11-18

## 新增
- 双协议首版：VLESS + WebSocket + TLS + Nginx；VLESS + REALITY + Vision。
- REALITY 默认端口 8443，提供 dest、SNI、端口和密钥参数的基础管理。
- 中文文档补齐原脚本的准备工作、安装方式、导入链接、注意事项、系统要求、修复说明、启动方式、相关目录、鸣谢和功能章节。

## 修复
- ACME HTTP-01 challenge 固定 webroot location。
- 统一 acme.sh 证书续期 reload hook。
- 续期后处理证书属主/权限，测试 Nginx 与 Xray 配置后再重载服务。
- 端口占用时只报告，不自动杀进程。

## 已知限制
- 这是开发版本，尚未完成 VPS 实机安装、自动续期和客户端互通验收。
- 仅明确支持 Debian/Ubuntu。
- 尚未实现 Xray 前置 TLS/回落安装模式。
- geoip.dat/geosite.dat 目前仅记录约定路径，安装脚本不自动下载。

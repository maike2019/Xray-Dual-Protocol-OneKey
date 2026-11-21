# 1.x 到 2.x 迁移说明

2.x 引入新的状态登记文件 `/etc/xray-dual-protocol/state.json`，并将项目管理的 Nginx 路由统一聚合生成。1.x 使用 `dual-ws`、`dual-reality` tag 和旧版 `installed` 文本状态，二者的数据结构不同。

**当前版本不执行自动迁移。** 如果检测到旧版 `dual-ws` / `dual-reality` 入站，但不存在 2.x 状态文件，安装脚本会停止，不会自动重写旧入站或 Nginx 配置。

在迁移工具完成前：

1. 不要直接在承载生产流量的 1.x VPS 上运行 2.x 安装脚本。
2. 备份 `/usr/local/etc/xray/config.json`、`/etc/nginx`、`/ssl`、`/etc/xray-dual-protocol` 和 acme.sh 配置。
3. 在新 VPS 或可回滚的测试环境中部署 2.x，逐项重新创建七种入站。
4. 使用客户端逐条验证连接后，再切换域名/DNS 或业务流量。
5. 确认新环境稳定后，才下线旧环境。

不要通过手工创建空 `state.json` 绕过检测。这会让旧版入站失去项目登记，且旧版 Nginx 规则可能被新聚合配置替换。

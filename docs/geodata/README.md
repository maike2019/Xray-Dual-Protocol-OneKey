# Xray geodata 文件

本项目约定可选文件路径：

- `/usr/local/share/xray/geoip.dat`
- `/usr/local/share/xray/geosite.dat`

它们是数据文件，不是目录。当前安装脚本不自动下载、更新或校验文件。使用时请确保 Xray 配置中的 `geoip:` / `geosite:` 路径与实际文件位置一致，并从可信来源获取数据。

# ADR-11 · 依赖与 Blender MCP 安全门

状态：Accepted

## 背景
第三方 Blender MCP 支持任意 Python、未认证本地 Socket，部分版本带遥测/第三方服务。

## 决定
本轮不安装/启用 MCP。以 factory-startup + disable-autoexec + 项目脚本建模；保留用户确认后的版本锁定、审计和回环连接方案。

## 备选方案
全局 uvx 最新版本；公开 9876；修改宿主 Codex 配置。

## 代价与限制
MCP 交互建模尚未交付；CLI 可完整执行本轮模型保存导出。

## 验证与复议条件
无新增 listener、无 sudo、无自动执行下载源码、无全局配置修改。
更改上述约束时必须更新本 ADR 或新增 superseding ADR；测试通过不自动代表用户视觉接受。

参考：[官方资料](../docs/research/README.md)。

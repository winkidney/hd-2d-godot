# ADR-01 · 渲染器与平台

状态：Accepted

## 背景
桌面高保真与浏览器能力不等价。

## 决定
Forward+；Linux 为首版验证平台；1080p/60FPS 是待测目标。

## 备选方案
Compatibility/Web；Mobile。

## 代价与限制
放弃首版浏览器运行；不用静默渲染器降级掩盖差异。

## 验证与复议条件
实际 GPU 启动并记录 renderer、分辨率、帧时间。
更改上述约束时必须更新本 ADR 或新增 superseding ADR；测试通过不自动代表用户视觉接受。

参考：[官方资料](../docs/research/README.md)。

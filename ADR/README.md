# ADR · 架构决策索引

Accepted 表示采用该架构，不代表所有代码/视觉已验收；Proposed 需要实际画面对照后定稿。

| ID | 决策 | 状态 |
|---|---|---|
| 01 | [渲染器与平台](01-renderer-platform.md) | Accepted |
| 02 | [三维世界与二维角色](02-scene-actor.md) | Accepted |
| 03 | [固定透视镜头](03-camera.md) | Amended by ADR-15 |
| 04 | [像素密度与采样](04-pixel-sampling.md) | Accepted |
| 05 | [角色受光、透明与落地](05-sprite-lighting.md) | Accepted |
| 06 | [灯光与后处理](06-lighting-post.md) | Amended by ADR-14/15 |
| 07 | [风格化水面](07-water.md) | Accepted |
| 08 | [Blender 与图像素材管线](08-asset-pipeline.md) | Accepted |
| 09 | [可复现与版本](09-reproducibility.md) | Accepted |
| 10 | [验收与交付](10-delivery-validation.md) | Accepted |
| 11 | [依赖与 Blender MCP 安全门](11-dependency-security.md) | Accepted |
| 12 | [静态模型扁平化烘焙](12-static-scene-baking.md) | Accepted |

## P6/P7 增强
[ADR-13：可行走横向路径与默认探索视差](13-walkable-parallax-route.md) — Accepted（功能方向），路线和相机已实施，验收见 P6/P7 报告。
此前对话中的后续编号仅为预留，本仓库采用连续实际编号；不得把需求接受等同于代码已经实现。

[ADR-14：原生双端景深](14-native-dof-control.md) — Accepted。
[ADR-15：默认开阔构图与背景](15-open-world-background.md) — Accepted。

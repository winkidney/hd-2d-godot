# 文档总索引

## 决策与范围
[Plan](../Plan/README.md) 是阶段与出口条件；[ADR](../ADR/README.md) 是取舍记录；[domain-model](../domain-model/README.md) 是统一语言和不变量。三者描述同一工程，不各自维护一份相互冲突的功能清单。

| Topic | 入口 | 内容 |
|---|---|---|
| 操作与预览 | [操作手册](operation/README.md) | 输入、展示、截图、编辑器与排障 |
| 设计与美术 | [设计要点](design/README.md) | 构图、像素密度、受光、已知美术限制 |
| 美术规格 | [初始美术方向](art-direction/README.md) | 资产规格与替换要求 |
| 运行架构 | [架构说明](architecture/README.md) | 脚本边界、坐标、碰撞、烘焙 |
| 素材管线 | [重建与替换](assets/README.md) | 原图、Blender、GLB、ImageGen 接入口 |
| 流程图 | [Mermaid + SVG](workflows/README.md) | 运行时、素材、交互、验收交付 |
| 验收 | [基线报告](validation/baseline-report.md) | 实测条件、结果、证据与限制 |
| 验收设计 | [测试策略](validation/README.md) | 代码正确与视觉批准的区别 |
| 交付 | [打包与重建](delivery/README.md) | 独立运行、源包、模板和校验 |
| 依赖安全 | [依赖说明](delivery/dependencies.md) | 复用环境、锁定版本、MCP 安全门 |
| 研究 | [官方资料](research/README.md) | 引用来源与事实/实现选择的区分 |

## 维护方式
改交互时同步领域契约、操作手册和运行测试；改素材生成时同步 manifest 与重建证据；改渲染时重新生成固定机位对照图。
运行日志只在 `build/`，已审阅的基线截图与 JSON 放在 `docs/media/`、`docs/validation/evidence/`。文档必须使用相对链接；`make test` 检查链接和常见私有主机路径。

## P6/P7 当前功能
[开阔探索设计](design/open-exploration.md) · [景深与背景领域模型](../domain-model/background-and-focus.md) · [本轮验证与证据](validation/p6p7/README.md)

## P8 可调视差
[操作](operation/parallax.md) · [验收与实拍](validation/p8/README.md) · [运行关系图](workflows/parallax-control.svg)。

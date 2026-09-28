# 需求 → 计划 → 实现 → 验收

| ID | 用户目标 | Plan/ADR | 实际实现入口 | 验收证据 |
|---|---|---|---|---|
| R01 | 原创 HD-2D 场景 | P2/P3; ADR 01/03/04 | scenes/waystation.tscn、scenes/world.tscn | 固定机位实拍；最终美术 Review 待定 |
| R02 | 2D 角色融入 3D | ADR 02/05 | scripts/pixel_actor.gd | 图集/脚底/受光；四向移动，主镜头实拍 |
| R03 | 黄昏/夜晚 | ADR 06 | scripts/lighting_controller.gd、resources/*.tres | 两套 GPU 图；原子切换与角色身份断言 |
| R04 | 行走与交互 | P4 | scripts/waystation.gd、pixel_actor.gd、hud.gd | 双向过桥、碰撞、最近交互与输入锁断言 |
| R05 | 水面与景深 | ADR 06/07 | shaders/water.gdshader、lighting_controller.gd | 夜晚 effects on/off；没有真实倒影 |
| R06 | Blender 源文件 | ADR 08 | art_source/blender、tools/build_models.py | 保存/GLB 导出、源文件检查、干净重建 |
| R07 | Plan/ADR/domain-model | P0 | 根 README 与三个顶层目录 | 静态文档链接/私有路径检查 |
| R08 | 可交付、可复现 | ADR 09/10/12 | Makefile、tools/reproduce.py、verify_release.py、package.py | 干净重建、独立二进制测试、归档散列 |
| R09 | 高风险依赖确认 | ADR 11 | dependencies.lock.json、docs/delivery | MCP 未启用；已有 CLI 制作链可用 |
| R10 | 可编辑流程图 | P0/P5 | docs/workflows/diagrams.json、tools/render_diagrams.py | 七份 Mermaid 与七份 SVG；make docs 重建 |

统一功能断言在 `tests/runtime_validation.gd`，素材/来源/文档检查在 `tests/check_project.py`，真实 GPU 计时在 `tests/render_benchmark.gd`。结果与限制见[验收报告](../docs/validation/baseline-report.md)。
未实现的 ImageGen/MCP 接入、音频、战斗和高级水面不得从本矩阵推断为已完成。

## P6/P7 已实现追踪
| ID | 需求 | 实现 | 验收 |
|---|---|---|---|
| R11 | 独立双端景深与调参 | dof_controller / dof_profile / dof_panel | 状态断言、棋盘近远选择性像素检查 |
| R12 | 默认探索见山见天 | camera_rig / background_rig / background.json | 18张构图、7处路线样本 |
| R13 | 横向路径与自然视差 | world_layout.walkway / world_builder | 连通、完整往返、相机行程、三层投影 |
| R14 | 独立云风与三时段 | background_rig / lighting_controller | 云与相机独立、时段身份保持 |
| R15 | 新功能交付闭环 | features / verify_features / reproduce / package_features | 指纹、独立包、干净重建、校验和 |

## P8 已实现追踪
| ID | 需求 | 实际实现入口 | 实际验收 |
|---|---|---|---|
| R16 | 总强度、逐层倍率、自然基线 | ParallaxProfile / ParallaxController | 倍率几何与像素、回位无漂移、旧自然模式回归 |
| R17 | 运行时面板、镜头参数和连续云风 | ParallaxPanel / CameraRig / CloudPhase | 面板互斥、输入锁、调速连续、视差与风分离 |
| R18 | 本机保存与新交付闭环 | ParallaxSettingsStore / P8验证工具 | 保存恢复、损坏回退、忽略用户配置、指纹与独立包 |
详细规格见 [P8计划](../Plan/features/adjustable-parallax.md) 与 [领域契约](parallax-control.md)。实现已完成，数据见[本轮验收](../docs/validation/p8/README.md)。

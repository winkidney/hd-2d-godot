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
| R10 | 可编辑流程图 | P0/P5 | docs/workflows/diagrams.json、tools/render_diagrams.py | 四份 Mermaid 与四份 SVG；make docs 重建 |

统一功能断言在 `tests/runtime_validation.gd`，素材/来源/文档检查在 `tests/check_project.py`，真实 GPU 计时在 `tests/render_benchmark.gd`。结果与限制见[验收报告](../docs/validation/baseline-report.md)。
未实现的 ImageGen/MCP 接入、音频、战斗和高级水面不得从本矩阵推断为已完成。

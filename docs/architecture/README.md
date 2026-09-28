# 运行架构与源码导航

| 模块 | 实现 | 责任 |
|---|---|---|
| 组合根 | `scripts/waystation.gd` | 输入、生命周期、交互、显示模式与截图 |
| 静态世界 | `scenes/world.tscn` | 可编辑网格、河岸、桥和独立碰撞 |
| 世界作者工具 | `scripts/world_builder.gd`、`tools/bake_scene.gd` | 固定种子生成并保存静态节点 |
| 玩家 | `scripts/pixel_actor.gd` | CharacterBody3D、移动状态、朝向与 Sprite3D |
| 灯光 | `scripts/lighting_controller.gd` | 环境、主光、点光、景深、预设应用 |
| 值对象 | `scripts/lighting_preset.gd`、`resources/*.tres` | 黄昏/夜晚可调参数 |
| UI | `scripts/hud.gd` | 标题、提示、状态、对话面板 |
| 验收 | `tests/runtime_validation.gd`、`tests/render_benchmark.gd` | 功能断言、截图和独立 GPU 计时 |

## 空间与可行走性
Y 为上，单位按米处理。玩家节点原点在脚底，胶囊半径 0.26、高 1.35，显示像素尺寸 0.045；精灵偏移不影响碰撞。
河流视觉面与可行走性完全分离。河岸外侧有水域阻挡，桥有独立连续碰撞面与护栏碰撞，建筑有简化包围盒。码头目前只作装饰，不能从岸边进入水域。
布局 JSON 管理镜头、建筑、灯位与交互位置；桥面/河岸碰撞的部分尺寸仍是 builder 中的场景常量。改变河流宽度或桥位置必须一起调整碰撞并重跑双向通行测试，不能假设只改 JSON 即可自动适配。

## 静态场景的生命周期
运行读取已烘焙的 `world.tscn`，不会每帧或启动时调用 Blender。导入模型在烘焙时转成显式节点，清除 `scene_file_path` 后再设置 owner，避免“继承实例 + 重复子节点”的混合状态。
该决定修复了实际 GPU 退出的资源泄漏；代价是更改 GLB 不会自动更新已烘焙节点，必须 `make import && make bake`。详见 [ADR 12](../../ADR/12-static-scene-baking.md)。

## 测试注入
测试通过 `scripted_input` 提供世界平面移动向量，使用同一 `_physics_process` 和碰撞逻辑；不是直接把角色传送到终点后声称走通。place 仅用于设置各测试起点。
对话和展示模式锁定输入；灯光切换不重建 actor。截图只在实际完成绘制后读取 Viewport，headless 明确拒绝截图。

运行关系图见[流程图](../workflows/README.md)，约束见[领域契约](../../domain-model/contracts.md)。

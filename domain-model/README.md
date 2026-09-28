# Domain model · 场景样板而非完整 RPG

## 统一语言
| 概念 | 责任 | 不负责 |
|---|---|---|
| WaystationScene | 组合静态世界、碰撞、角色、灯光、镜头、交互点 | 美术生成、依赖安装 |
| WorldLayout | 坐标、道路/桥梁边界、建筑占地、生成种子 | 帧更新 |
| PixelActor | 世界位置、移动状态、朝向、显示帧、物理碰撞 | 对话内容存储 |
| InteractionPoint | ID、位置、触发半径、文本 | 自动远程调用 |
| LightingPreset | 主光、环境色、雾、局部光强的值对象 | 改动物理世界 |
| CameraRig | 固定方向、构图、有限跟随、景深 | 改变角色比例 |
| WaterSurface | 流动视觉与波纹 | 玩家可行走性 |
| AssetRecipe | 原料、参数、种子、产物与校验和 | 在线生成服务 |
| ValidationRun | 条件、断言、截图、性能原始样本、结论 | 代替用户美术批准 |
| DeliveryBundle | 已知版本、可运行资源、文档与限制 | 自动安装高风险软件 |

## 不变量
世界采用 Godot 右手坐标，Y 向上，单位为米；Blender 导出执行轴转换，禁止二次手工交换轴。
角色脚底是位置原点；精灵像素锚点统一；变更帧不得移动碰撞体。
角色移动由 CharacterBody3D 处理，水域是不可进入空间；桥是唯一通行连接。
只有最近且范围内的交互点可以响应；HUD 隐藏不停止世界模拟。
灯光切换不得重建角色或模型；快照必须在实际图形帧完成后保存。
生成种子必须固定；文件名/资源引用用相对路径；没有外部网络运行依赖。
所有源素材为本项目原创程序化生成，后续替换素材必须登记来源。

## 关系与事件
WorldLayout -> WaystationScene -> {PixelActor, InteractionPoint[], LightingPreset, CameraRig, WaterSurface}
AssetRecipe -> {Texture, SpriteAtlas, BlenderSource, GLB} -> WaystationScene
Input -> movement_requested / interaction_requested / preset_changed / capture_requested
ValidationRun 引用工程版本、资源散列与运行条件；不写入运行状态。

见 [状态与数据契约](contracts.md)、[需求追踪](traceability.md)、[流程图](../docs/workflows/README.md)。

## P6/P7 更新
新增背景、步道、相机和景深模型见 [领域扩展](background-and-focus.md)。CameraRig 提供最终姿态；DofController 拥有相机属性；BackgroundRig 不负责角色移动。

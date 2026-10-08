# ADR-22：横向河街、平面柳树和缓存夜空

状态：Accepted。接受用户已批准的场景结构；美术批准与工程验证分别记录。

## 决定

Ancient 默认布局改为横河，通过 `river.axis`、河中心、桥中心和码头接岸参数统一生成可走地面与碰撞。复用已有江南建筑和灯具，低矮石拱桥使用独立模型，不覆盖原桥。柳树改为固定 Y billboard 的像素 Sprite3D，近景保留阴影、背景不投影。角色动画与受光数据不变。

夜空是一张固定种子的 4096×2048 RGB 全景和缓存 Sky/ShaderMaterial。镜头横移只更新 `Environment.sky_rotation`；全景内星点、银河、月亮一起转动。启用依据为已存在的背景时段，保留 custom 调光与 schema 2 状态恢复。

## 景深

默认景深会模糊无限远天空，掩盖小弯月。普通透明叠层修改 DEPTH 无法保护 Godot 的已解析深度。采用只针对深度恰好为零的天空像素的 CompositorEffect，在 POST_TRANSPARENT、MSAA 深度解析后，把这些像素的深度写入当前焦距。建筑、水面及背景实体的深度不变；原有景深仍由 CameraAttributes 控制。

该通道不修改颜色，不分配额外全屏纹理，不逐帧修改天空材质。在项目默认的 Forward+ 与 2×MSAA 下使用可写的 R32 已解析深度；关闭 MSAA 时跳过保护通道，天空仍显示但会受原生景深模糊影响。其他渲染路径未验收。实际 GPU A/B 将全景和此通道一起计入夜空预算。

依据：[Godot RenderSceneBuffersRD](https://docs.godotengine.org/en/stable/classes/class_renderscenebuffersrd.html)、[CompositorEffect](https://docs.godotengine.org/en/stable/classes/class_compositoreffect.html) 和 [引擎深度解析格式实现](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp)。

## 验证边界

无窗口检查证明碰撞、交互、镜头和状态恢复；GPU 截图与往返证明实际画面；独立性能采样验证预算与反射更新。原布局与新布局路线不同，整体前后比较只反映各自可玩的场景负载；新布局夜空开关 A/B 用于归因。测试通过不代替用户美术批准。

见 [计划](../Plan/features/ancient-horizontal-night.md) 和 [执行报告](../docs/ancient-canal/horizontal-night-20261008/README.md)。

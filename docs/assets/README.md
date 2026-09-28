# 素材、模型与重建流程

## 当前来源
14 张源 PNG 来自 `tools/generate_assets.py`，seed=290928，规格与 SHA-256 在 `art_source/generated/manifest.json`。`make test` 在内存中重新生成图像并比对；校验失败应调查 Pillow 版本或生成器变化，不自动改写基线。
8 类模型来自 `tools/build_models.py`：inn、cottage、bridge、lantern、barrel、crate、dock、tree_trunk。每类保留 `.blend`、`.glb` 和源脚本；`.blend` 中贴图已打包。
这些是程序化原创素材，不是 ImageGen 已生成结果，也不是原作提取资产。Godot 导入 GLB 时产生的 `assets/models/*_wood.png` 等为派生副本，不应计作额外原创源图。

## 重建顺序
`make rebuild` 依次执行源 PNG → Blender 建模/保存/GLB 导出 → Godot 资源导入 → 静态场景烘焙。随后执行 `make test && make features-visual`。所有生成工具只写当前项目；不改其他 Blender 工程。
单独改布局或碰撞：编辑 `resources/world_layout.json` 与 `scripts/world_builder.gd` 后执行 `make bake`。单独改模型：`make models && make import && make bake`。
Blender→Godot 的轴转换只在生成器执行一次，禁止再手动交换导入轴。屋顶面绕序在源模型修复，不能用全场景双面渲染掩盖法线问题。
静态场景可以在编辑器修改，但下次 `make bake` 会覆盖 `scenes/world.tscn`；需要保留的改动应回写生成器/布局，或另存独立美术场景并形成新 ADR。

## 接入 ImageGen 或人工图像
先批准一张角色基准，再逐方向扩展；每帧统一画布、脚底锚点、尺寸和透明度。当前合约为 32×48、4 方向×4 帧，RGBA 图集 128×192，方向顺序 front/back/left/right。
源图归档到 `art_source/imagegen/` 或 `art_source/authored/`，记录原始文件散列、生成提示/版本/输入图、授权来源和后处理参数；没有实际原图不要建立虚假的来源记录。
生成大图不是合格动画。要检查跨帧头身比、装备位置、轮廓、半透明边缘和背景污染；在实际黄昏/夜晚灯光下对照。严格像素化、调色和 Alpha 清理应由可重复处理脚本完成。
替换程序化素材时新增来源类型和 manifest，不应继续用原生成器的 SHA 声称通过。可保留 procedural baseline 与新分支，以便对照。

## Blender MCP 安全门
当前仅使用已有 Blender CLI、`--factory-startup --disable-autoexec` 和项目自有脚本。MCP 第三方插件仍未启用；它不是运行或重建的必要依赖。
接入前须固定来源/版本、检查任意 Python 执行能力、遥测和回环监听范围；不开放公网端口，不修改现有用户工程。详见 [ADR 11](../../ADR/11-dependency-security.md)。

[素材流程图](../workflows/assets.svg) · [图结构源](../workflows/diagrams.json) · [实际验收](../validation/baseline-report.md)

## P6/P7 背景来源
新增3张256×96云图来自 `tools/generate_background_assets.py`，4套山体／地形来自 `tools/build_background.py`。来源清单在 `art_source/background/`，每套保留 `.blend` 与 GLB。总计17张原创源PNG和12套模型。
`make assets` 与 `make models` 同时覆盖原素材和背景；`make rebuild` 重新导入并烘焙道路。
角色纹理明确禁止3D自动压缩和mipmap；环境纹理使用mipmap，防止远景走动时闪烁。
背景实例在运行时组装，模型源仍可在Blender编辑；持久改动应回写生成器或作为显式人工源另行记录。

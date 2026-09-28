# ADR 12：静态模型扁平化后烘焙

状态：Accepted。日期：2026-09-28。

## 背景与问题
运行时临时生成几何不利于编辑器预览和交付。本轮将模型实例与碰撞保存成 `scenes/world.tscn`，但初版同时保留 GLB 实例状态与显式子节点，实际 GPU 退出出现遗留渲染资源与 ObjectDB 警告。

## 决策
烘焙时清空每个子节点的 `scene_file_path`，再设 owner 并打包 PackedScene。运行场景只保留显式节点和外部 Mesh/材质资源引用，不混用原实例状态与替换子节点。
`tools/bake_scene.gd` 负责落盘，`scripts/world_builder.gd` 是确定性作者工具。运行不执行 Blender，不安装编辑器插件。

## 备选
保留可编辑 GLB 子实例需要正确管理 editable instance owner 与覆盖关系，初版复杂度较高；纯运行时生成牺牲可交付编辑体验；手工独立制作失去可重复重建。

## 后果与代价
静态场景可直接查看和编辑，退出清理恢复正常；更改 GLB 后必须重新 import/bake。直接修改 baked 场景会被下一次重建覆盖，重要变更需回写生成器或在独立场景中管理。
GLB 与 blend 仍保留，Mesh 资源保持共享，不是每帧复制模型。

## 验证
`tests/check_project.py` 检查 world.tscn 不残留 `instance=ExtResource` 标记；headless 功能测试与真实 GPU 截图运行均实际清理场景并退出。修复后预览与完整测试日志无先前的资源泄漏 ERROR。
这是本项目实际排障结论，不声称所有 Godot 导入实例都会泄漏。关联 [ADR 08](08-asset-pipeline.md)、[架构](../docs/architecture/README.md)。

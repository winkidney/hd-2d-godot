# P9 四方案来源与工程完整性核验

核验日期：2026-09-29。检查点：`3b6333f7b7e3aab09ffac34b4a97ef8d75ac3475`。

本报告核验原图、历史基线、生产来源、运行资源引用和项目依赖边界。除已获授权的公开源码检查器修复外，核验未修改运行资源，未启动 Godot 导入、GPU 或 Blender。此结论不替代最终 GPU、美术与性能验收。

## 原图和历史记录

两张用户提供的 PNG 均存在，文件散列、解码后 RGBA 像素散列和尺寸与 `art_source/reference-scene/manifests/source-status.json`、`intake.json` 一致。

| 来源 | 路径 | 尺寸 |
|---|---|---|
| 原创模块素材板 | `art_source/reference-scene/originals/town-module-board-upload-20260929.png` | 1448×1086 |
| 运河扩展概念图 | `art_source/reference-scene/originals/canal-extension-concept-upload-20260929.png` | 1672×941 |

```text
素材板文件 SHA256
48db5064440c2a2562591ea42eaec7a485f02b272a29743afc08f02bea19d3a0
素材板 RGBA 像素 SHA256
fb4a2df5adf65140b1c7ebac304a4caa50b354d89c965a7733377ecd128313ba

概念图文件 SHA256
6a5a13bbf85e044b3670c71e9a9a9fb32863fb95b1275dbc4c8bbf83dcda94ad
概念图 RGBA 像素 SHA256
4eb0e61896b62124e82eb78d1ed36075134391d167c41d07d520b877b1346688
```

素材板的历史工具记录为 `ff85aae1ce6b117ad597bc5932a4a2f01eacbc61140df3a2860fd1a59ba138ed`。新原图与其字节不一致；清单保留两者及差异说明，没有把本次上传声称为历史文件的字节级副本。历史 `approved-intake.webp` 仍保留，但不再作为当前生产输入。

`art_source/reference-scene/baseline-3b6333f/` 中核验了 195 个文件，均与检查点相应 Git blob 完全一致，无缺失映射或不同字节。其中包含 23 张旧运行 PNG、16 个 GLB、16 个 `.blend`，以及旧处理脚本和清单。基线目录没有 `.blend1` 副本。

`project.godot` 的当前散列为 `abb14bd9dae624ff5d6931419ba6b75925ea8fc52ba7135d3f6a7e7d2442a4fc`，与已提交检查点一致。旧共享基线 `e88fea7e…` 保留未改；`source-status.json` 中的 `checkpoint_baseline_exceptions` 说明检查点已清理显式引擎默认值。该差异并非本轮实验面板引入。

## 生产链和运行引用

`tools/p9/process_assets.py` 从素材板原 PNG 直接读取裁切区域，经必要的四边形校正、去底、调色、量化与 atlas 组装生成资源。当前清单包含 18 张非角色纹理和 5 张角色 atlas。研究截图与概念整图没有进入此采样流程。

`tests/p9/check_assets.py` 校验了源文件、像素、配方链接、atlas 尺寸与脚点、周期边缘、模型容器和 `.blend` 散列，并确认所有 GLB 内嵌纹理像素与当前处理素材一致。模型清单保留生成时的整体处理清单散列，另用纹理子清单散列绑定实际模型输入，因此后续角色去底修复不要求重新生成未变化的模型。

D 的来源由 `tools/p9/capture_impostors.gd` 和 `assets/reference-scene/impostors/manifest.json` 描述。三时段图集散列均匹配，七个视角为 `−24/−16/−8/0/8/16/24°`。模型来源为 `assets/reference-scene/models/palazzo.glb`，其散列仍为 `b9b5e764f50c50532ce89b8b354b85d51cef4ffcc92dd4eee8c58e117f72d4f5`。D 使用该模型的离线渲染图集，不是概念整图。

对 `scripts/`、`scenes/`、`resources/`、`assets/` 和 `project.godot` 搜索原作截图、两张上传原图及 `art_source`、`originals/`、`research/` 路径，没有运行引用匹配。对运行资源目录中的 111 张 PNG 比较文件及 RGBA 像素散列，没有发现原作截图或两张上传整图的直接副本。`art_source/.gdignore` 也仍存在。

这些检查证明本工程的直接资源引用及已记录生产链边界，不构成对生成图原创性、相似性或第三方权利的法律认证。

## 依赖和 Blender MCP

`dependencies.lock.json`、`docs/delivery/dependencies.md` 和 `project.godot` 与检查点相比未改变。项目变更中未发现新增包管理清单、Godot 外部插件、MCP 配置、Blender MCP 服务入口或安装命令。Blender 重建使用既有 CLI 的 `--background --factory-startup --disable-autoexec --python` 路径。四种运行方法由项目内 GDScript、Shader 和既有引擎能力实现。

版本记录有一处需要读者区分：历史依赖清单的 `pillow_tested` 是 `11.3.0`，本轮 `processed.json` 记录的实际生产版本是 `12.3.0`。本轮相同字节重建证据对应现有 `12.3.0`，不声称旧版 `11.3.0` 会产生完全相同字节。此项不表示本轮安装了新依赖。

这是项目代码和已记录执行路径的核验，没有扫描或认证整台主机上其他任务的插件、进程或软件状态。

## 公开源码边界和严格检查

审计发现并修复了公开源码包的检查器兼容问题：打包按计划不分发原作研究截图，旧检查却无条件读取它。现在研究图存在时校验文件散列；缺席时明确输出 `PASS research_not_distributed_expected`，同时要求 `runtime_usage=false`、合法 SHA256 和来源记录一致。两张生产原图仍必须存在。

验证结果：

- 当前工程：`P9_ASSET_CHECKS 571 failed 0`，真实退出码 `0`。
- 按实际 `source_files` 打包边界复制到隔离目录，共 928 个文件，未复制 `research/`，两张生产原图完整保留：571 项通过，退出码 `0`。
- 仅在隔离副本中暂时移开素材板原 PNG：检查返回退出码 `1`。
- 前一次只读散列损坏模拟也确认 `hero.png` 损坏会报告失败并退出 `1`。
- 修改后的检查器通过 `git diff --check`；没有更改运行资源。

因此公开源码包可保留完整原创建材输入和重建流程，同时排除原作截图。最终 ZIP 内容、独立运行和 GPU 结果仍由交付验收报告单独给出。

## 本次核验文件指纹

```text
tests/p9/check_assets.py
34d0aac46d04b19cda7e5d5e8f6b417ff2fef02e1edd66bcda1a23ddd8f70b8f

dependencies.lock.json
83f387f6ea63910057b5cccfd14a2e073e5e0a313a3330b966d2c81a3fd1d6c7

art_source/reference-scene/manifests/processed.json
d18a63b69753aa9e177c601e157f41672dd423a72416e669b6ccb276583e1c72

art_source/reference-scene/manifests/models.json
05f2c99c9a232edc98843137bfb475eefaec562c17c51567f6b3114b47e9be52

art_source/reference-scene/manifests/source-status.json
d028ccc6fbc11558d7aab1057a3fbe75ebba2db48b619df5c82fc5dcbdd497de
```

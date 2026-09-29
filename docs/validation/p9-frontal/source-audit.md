# P9R2 来源与工程隔离审计

历史快照说明：本报告及manifest中的`1068…`指纹属于新增可调镜头之前的初始P9R2版本，所有原审计散列保留。之后的镜头改动和纹理导入配置不包含在此报告结论中；当前提交状态见[提交前校验](../p9-frontal-zoom/commit-check.md)。

审计日期：2026-09-29。比较点为 `171e632358fa3f8d370089b29f9d47e5024fac7a`。

结论：在本次源码、散列和分发边界检查范围内通过。P9R2 复用已经提交的原创素材链，只新增独立世界与 F/W/O 透视镜头；没有重新生成 ImageGen 图，也没有修改旧纹理或模型。此结论不等同于视觉批准或版权法律意见。

## 1. 原图和处理链

两张用户重新上传的 PNG 均按原字节保留。SHA256 重新计算后与旧来源记录一致；像素散列按 `convert('RGBA').tobytes()` 计算，尺寸另列。完整记录见 `art_source/frontal-canal/manifest.json`。

| 原图 | 尺寸 | 文件 SHA256 | RGBA 像素 SHA256 |
|---|---|---|---|
| `art_source/reference-scene/originals/town-module-board-upload-20260929.png` | 1448×1086 | `48db5064440c2a2562591ea42eaec7a485f02b272a29743afc08f02bea19d3a0` | `fb4a2df5adf65140b1c7ebac304a4caa50b354d89c965a7733377ecd128313ba` |
| `art_source/reference-scene/originals/canal-extension-concept-upload-20260929.png` | 1672×941 | `6a5a13bbf85e044b3670c71e9a9a9fb32863fb95b1275dbc4c8bbf83dcda94ad` | `4eb0e61896b62124e82eb78d1ed36075134391d167c41d07d520b877b1346688` |

素材板历史工具记录为 `ff85aae1ce6b117ad597bc5932a4a2f01eacbc61140df3a2860fd1a59ba138ed`，与重新上传 PNG 不同。原记录与差异说明没有重写，不能声称两者字节相同。历史 `approved-intake.webp` 仍保留，但不是当前生产输入。

生产链从素材板原 PNG 直接裁切，执行 QUAD 透视校正、边缘连通去纸底、角色脚底纸面阴影清理、调色、像素化、二值透明与 atlas 组装。保留 18 张 64×64 纹理及 5 张 192×256 角色图集，每帧 48×64。延伸概念图只用于构图研究，不参与运行纹理裁切。

| 记录 | SHA256 |
|---|---|
| `art_source/reference-scene/manifests/intake.json` | `876abf45ee1b6773a7542bb00e916ca67ee0660b623d0172bc7b1369202ab5d8` |
| `art_source/reference-scene/manifests/processed.json` | `d18a63b69753aa9e177c601e157f41672dd423a72416e669b6ccb276583e1c72` |
| `art_source/reference-scene/manifests/models.json` | `05f2c99c9a232edc98843137bfb475eefaec562c17c51567f6b3114b47e9be52` |

`models.json` 的完整输入清单散列保留模型生成时的快照；之后仅角色脚底清理改变了角色记录。模型依赖的纹理记录投影散列仍为 `ed30c1b039ee029b45dea8eeb921e0dbd7228922dc80be873e764d407abfe674`，与当前 `processed.json` 一致。检查器逐项验证 GLB 内嵌图片像素，未用修改历史散列的方式掩盖差异。

## 2. 与已提交工程逐文件比较

读取 Git 比较点的 946 个 blob，以当前文件内容重新计算 Git blob 标识，确认字节一致性。审计时旧的跟踪文件仅 `Makefile`、`Plan/README.md`、`domain-model/README.md` 有变化，分别增加新入口和索引，没有修改旧入口逻辑。

| 检查范围 | 文件数 | 与比较点不同 |
|---|---:|---:|
| 原有 `assets/scripts/scenes/resources/shaders` 及项目、导出、依赖配置 | 362 | 0 |
| `assets/reference-scene` 下全部既有 PNG，包括保留的旧四方案图集 | 76 | 0 |
| P9 模块 GLB | 16 | 0 |
| P9 模块 `.blend` 源 | 16 | 0 |
| `art_source/reference-scene/baseline-3b6333f` 历史基线 | 195 | 0 |

`tools/p9/process_assets.py`、`tools/p9/build_models.py`、`tools/source_files.py`、`export_presets.cfg` 和 `dependencies.lock.json` 也未改变。新工具中没有安装依赖或启动 Blender MCP 的调用。本轮未执行安装、Blender、Godot 导入、GPU 捕获、提交或推送。

## 3. 新场景绑定

新入口为 `scenes/frontal_canal.tscn`，烘焙世界由 `tools/p9frontal/build_world.gd` 调用 `scripts/frontal_canal/world_builder.gd`，读取 `resources/frontal-canal/layout.json`，随机种子为 290929。模型、材质、实体碰撞与镜头分离。两岸外侧补地是非碰撞装饰，不扩大可行走边界。

| 文件 | SHA256 |
|---|---|
| `scripts/frontal_canal/world_builder.gd` | `de9faf887d6b2ddfa6e89c091039f0be6aea084cce27d4716c0d573a5f66ca0c` |
| `resources/frontal-canal/layout.json` | `e3a63ae2cf491b68732eefdb5812ac0e7ea76c85c774c1900ea188e7fed0a14e` |
| `scripts/frontal_canal/camera.gd` | `22824270e7a2b0aa6d5cdaac4cda09943fc1aa35da7820e3d8a27f9fbe11071c` |
| `scenes/frontal_canal_world.tscn` | `8034251081c468f491899409bbb5fd1021acd3fe2ab128c536131f698d2843b7` |

最终镜头参数来自新独立 `camera.gd`，F 为 35°FOV、14°俯角、30m 半径；W 为 45°FOV、12°俯角、23m 半径；O 使用 F 的投影并增加 ±4°位置驱动偏航。三组均显示真实三维建筑，不使用旧 D 的建筑多视图图集替代墙面。

当前运行及测试文件指纹为 `1068e938e4ce7b30b3e62d3e26124ab95d47d49107942c2dc19bb312a379293e`，与已有 `build/p9-frontal/gpu/report.json` 一致。该报告记录 362 项 GPU 检查通过；本审计只读取它，没有重新跑 GPU。

## 4. 原图不能替代场景

扫描 60 个运行脚本、场景、资源与 shader 文本，未发现原图路径、原图文件名、原作截图或历史有损 intake 的运行引用。对 `assets` 下全部 111 张 PNG 计算文件散列与 RGBA 像素散列，未找到两张原图或原作截图的整图副本。571 项 `tests/p9/check_assets.py` 检查全部通过，退出码为 0，涵盖原图、处理配方、运行图片、GLB 内嵌纹理和 `.blend` 来源。

这些检查结合生成脚本证明当前素材链没有从原作截图裁切纹理或角色，但不能代替对任意视觉相似性的法律判断。

## 5. 分发边界与验证限制

`tools/source_files.py` 使用明确目录白名单，拒绝符号链接、缓存、`.env` 和 `.blend1/.blend2` 备份。`tools/p9frontal/run.py` 与 `package.py` 进一步排除路径中的 `research` 目录；当前排除的是原作研究 PNG 和 `docs/research/README.md`。

按实际选择函数枚举后，两张 ImageGen 原图、16 套 `.blend/.glb`、处理脚本、建模脚本、配方与新世界构建入口都在源码分发集合中。导出配置排除 `art_source/docs/Plan/ADR/domain-model/tools/build`，原作截图不进入独立运行包。打包工具可以单独制作研究对照图，该图不属于源码包或运行包。

本次没有重新建包或打开新 ZIP，也没有重跑图像生成、Blender 生成、干净重建与视觉验收。分发结论针对已读到的选择器和包生成逻辑；最终 ZIP 成员、启动结果与 SHA256 应由交付验证另行确认。已记录的纹理处理版本为 Pillow 12.3.0、模型生成版本为 Blender 5.2.2 LTS，不能把本次字节一致性检查表述为跨版本重建证明。

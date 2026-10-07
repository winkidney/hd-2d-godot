# HD-2D · 江南河街

项目默认进入古风场景 [江南河街·桥头酒肆](docs/ancient-canal/README.md)：两岸街道、石拱桥、酒肆、摊位、木码头及三名驻点 NPC。默认角色复用 A 稿四方向的 108 张 256×256 颜色帧，逐帧法线与银饰蒙版用于动态三维受光。F／W 两种固定朝向镜头提供角色居中跟随、六层远景视差及近远景深。

原默认驿站和其他历史场景保留为存档、技术比较与美术参考，需要单独打开。它们的场景文件、素材、制作来源和历史验收证据保持。

## 启动与操作

在包含 `project.godot` 的目录执行：

```bash
make run               # 默认进入江南河街，需要已有图形桌面
make editor            # 打开工程；F5 运行江南河街，F6 运行当前打开的场景
make canal-run         # 显式运行江南河街
make canal-test        # 江南素材、场景、设置与镜头的无窗口检查
make canal-camera-test # F/W 居中跟随专项检查
make test              # 历史驿站与共用角色的无窗口回归
make export            # 江南 Linux 导出流程
make package           # 江南完整交付流程
```

主场景为 `scenes/ancient_canal.tscn`。WASD／方向键行走，E 对话或调查，M 打开中文光影控制台，T 切换时段，G 开始自动路线，K 截图。控制台可调角色法线、银饰高光、各组灯光、景深、视差及镜头。自动路线中按移动键或 Esc 接管，面板关闭时滚轮调整镜距。

Tab 只移动界面焦点；文本编辑和修饰键不会触发普通场景操作。F8／F9 留给 Godot 编辑器停止／暂停。Esc 逐层关闭路线、菜单、面板和对话，退出需确认。

设置仅在主动保存时写入江南场景的独立配置；截图位置由界面显示。`GODOT` 可指定已有引擎，运行不依赖 Blender、生成服务或其他仓库。详细说明见[江南操作与光影控制台](docs/ancient-canal/README.md)及[启动与操作](docs/operation/README.md)。

## 全流程 Runbook

本节按当前江南主场景串起制作链。每步说明目的、来源、操作、提示词要点和检查出口；人工选稿、结构修正与视觉复审仍需实际完成。

| 复现路线 | 怎么做 | 能复现到什么程度 |
|---|---|---|
| 归档素材重建 | 复用原颜色帧、母图、结构层和固定配方，运行贴图／模型／NPC／法线脚本 | 原角色颜色与时序保持；加工结果按清单核对。不同工具版本的文件编码可能不同 |
| 重新生成素材 | 用原设计和提示词生成新母图／动画，人工选稿后再走相同加工链 | 复现画风和约束；ImageGen未提供内部版本或seed，不能保证同图。H3固定seed也需匹配模型和环境 |

所有本项目命令在工程根执行。重建会写入素材与可编辑来源，应在独立工程副本进行；保留原始输入、淘汰稿和历史报告。以下 `RUN` 使用一个新的工程内目录，每次复现更换编号：

```sh
RUN=build/ancient-canal/repro-001
```

### 1. 确定设计与环境

- **目的**：用清楚的像素角色、真实三维建筑、冷暖灯光与景深形成HD2D层次，先保证人物服饰可读和路线可走。视觉方向参考[开发者访谈](https://www.unrealengine.com/developer-interviews/octopath-traveler-ii-builds-a-bigger-bolder-world-in-its-stunning-hd-2d-style)，角色与场景为本项目自己的设计和实现。
- **输入与来源**：[用户角色设计](art_source/characters/crescent-traveler/v1/reference.png)、[版本锁](dependencies.lock.json)、[技术资料索引](docs/research/README.md)和[来源许可](NOTICE.md)。Godot与导出模板版本必须一致；公开stable文档不代替锁定引擎的实际检查。
- **操作**：先用 `make run` 确认已有工程，再为制作准备下表工具；本项目没有自动安装全部制作环境的命令。重新生成动画需要另行准备对应模型、Python与GPU环境。
- **提示词要点**：靛蓝／朱红／银饰呼应青瓦白墙、木构与暖灯；清楚像素簇和轮廓，避免模糊或满屏小人物。比例、角色设计和观察方向作为共同输入固定。
- **产物与检查**：保存版本、输入摘要、参数和来源；ImageGen未知版本／seed记为null，程序结构seed与H3seed分别记录。

| 工作 | 工具与资料 |
|---|---|
| 运行 | 已有Godot Forward+与显卡驱动；独立Linux包不需要制作工具 |
| 贴图／模型／法线 | Python、Pillow、NumPy、OpenCV、fontTools和后台Blender；锁文件记录Godot／Blender／Python／Pillow的已测版本，其余依赖另行准备 |
| 新母图／行走动画 | 内置ImageGen；H3／ComfyUI、ToonOut、GPU环境及Aseprite。动画制作采用尚未公开的JIBIJIBI-GAME流程，这里仅作简述 |
| 编码／导出 | ffmpeg、ffprobe和匹配Godot的项目内导出模板；字体OFL与第三方声明随包保留 |

### 2. 制作角色动画

- **目的**：先固定角色身份与运动，再确定像素密度。采用动画A的平稳步态；256原生画布用于保留月饰、刺绣、裙褶和双辫。角色动画A／B／C表示平稳／轻快／舒展，与下一步的场景概念A／B／C不是同一组选稿。
- **输入与来源**：[母图提示词](art_source/characters/crescent-traveler/v1/masters/right.prompt.txt)、[原始回执](art_source/characters/crescent-traveler/v1/masters/right.imagegen-receipt.json)、[来源映射](art_source/characters/crescent-traveler/v1/masters/right.provenance.json)及[四方向配方、源视频和选帧](art_source/characters/crescent-traveler/v1/generation)。已有成果直接复用[角色资源](assets/characters/crescent-traveler/v1/character.json)，无需重跑模型。
- **操作**：新母图保持三分之四向右全身姿态和透明背景；整段统一转换至768×768、可见高度648、脚底Y=720。H3每方向56帧、24fps、40步、1800秒预算；右／左／前／后seed为41／141／241／442。左、前、后独立生成，背向341转身稿保留为淘汰记录，不能简单镜像A。
- **提示词要点**：服饰层次、纹样和饰品连接点保持；持续匀速原地走，不转身或停顿，H3背景统一洋红色；银饰随步态有重力延迟，硬月冠不弯曲，裙褶由腰胯带动，发辫轻微滞后。背面不画正面脸、胸饰、腰扣或围裙。完整原文在各方向 `prompt.txt`。
- **产物与检查**：ToonOut抠图后直接输出256×256，固定裁剪、每方向最多96色、二值Alpha、透明RGB归零、最近邻与无mipmap。本次归档采用连续源帧28～54，每方向27帧／1125ms，保留41／42ms和脚底 `(128,240)`，不跳帧、插帧或逐帧居中；新生成需重新审查完整步态与接缝后选连续区间，不能机械套用旧区间或覆盖已批准A。保存PNG、图集、时间线与Aseprite；用 `python3 tests/check_character.py` 核对现有资源，实际循环另行视审。[详细角色来源](art_source/characters/crescent-traveler/v1/README.md)

JIBIJIBI-GAME尚未公开，其动画流程在这里仅作概述：方向母图与步态提示词输入H3，人工审查源动画，再经ToonOut抠图、像素化和连续循环选帧。模型安装、服务配置及作业管理细节暂不展开。

本项目已归档采用的提示词、参数、源视频和最终颜色帧，可直接复用现有成果；游戏运行不依赖JIBIJIBI-GAME。重新生成需要对应的模型与GPU环境，从颜色源动画到交付PNG的后处理尚无本项目的一键重建入口。

### 3. 概念设计与灰盒路线

- **目的**：先比较构图并验证通路，再投入正式建模，避免桥坡不可走、酒肆浮水或主角太远。
- **输入与来源**：[三稿、原图、裁切、提示词与回执](art_source/ancient-canal/concepts/2026-10-07/README.md)、[米制布局](resources/ancient-canal/layout.json)与原角色。概念人物只作尺度参考，不能替换运行序列帧。
- **操作**：相同参考、资产清单、像素密度和黄昏光照，并发生成桥头酒肆／沿河长街／两岸市集；逐稿修订并人工选择A，再用实际灰盒截图做布局适配。新制作应带入当前F／W镜头；原概念的旧俯视构图作为历史保留。
- **提示词要点**：完整人物和屋顶，清楚的两岸／桥头路线与平缓桥坡；青瓦白墙、木构、石岸、酒肆、两类摊位、码头和船；无UI、拼贴或马赛克滤镜。只改变构图关系，详细纹样不能被远景吞没。
- **产物与检查**：保留全部候选、选型理由、布局与近景裁切；先检查两岸、桥、酒肆门口和码头，再进行正式美术：`python3 tools/ancient_canal/validate.py --mode blockout --output-dir "$RUN/blockout"`。

### 4. 制作贴图、真实模型与NPC

- **目的**：颜色图负责像素风格，真实几何负责侧面、桥底、遮挡和投影；微细受光结构独立制作，避免把固定阴影烘焙进颜色。
- **输入与来源**：[材质母图与结构](art_source/ancient-canal/textures/README.md)、[Blender模型来源](art_source/ancient-canal/blender/README.md)、[NPC母图与结构](art_source/ancient-canal/npcs/README.md)。
- **操作**：材质母图最近邻加工，128像素象限镜像组成256周期单元；瓦缝、木纹、石缝和刺绣使用独立结构高度。后台Blender生成真实建筑、拱桥与道具，保留blend和GLB。掌柜、摊主、船工各用独立母图，制作同尺度驻点站姿，本轮没有NPC行走动画。
- **提示词要点**：材质为正交平面、均匀光、无投影／透视／渐变，横纵可平铺；建筑参考显示完整三分之四体积；NPC全身、透明背景、双脚同基线、服饰完整、柔和中性光。[材质完整提示词](art_source/ancient-canal/textures/prompt.txt)
- **产物与检查**：颜色／法线贴图、可编辑模型、UV、切线和NPC三种材质图。检查周期边界、模型重开、GLB向量与内嵌纹理；NPC颜色、法线和蒙版共享Alpha与 `(128,240)` 脚底。

```sh
python3 tools/ancient_canal/build_models.py --textures
blender --background -noaudio --factory-startup --disable-autoexec --python tools/ancient_canal/build_models.py -- --batch-exit
blender --background -noaudio --factory-startup --disable-autoexec --python tools/ancient_canal/build_models.py -- --verify-only --batch-exit
python3 tools/ancient_canal/build_models.py --verify-glb
python3 tools/ancient_canal/build_npcs.py
```

### 5. 绘制108帧角色法线

- **目的**：让脸、发辫、银饰和裙褶随动作稳定受光，同时保持原颜色与动画。法线是向量数据，不能套颜色调色板或用衣服亮度推凹凸。
- **输入与来源**：[复用摘要基点](art_source/ancient-canal/character-reuse.json)、[法线制作与修订](art_source/ancient-canal/character-normals/README.md)。每方向取0、6、13、20、26及待机帧，ImageGen六姿态板只辅助理解体积，不采样成运行法线。
- **操作**：定义脸、头发、发辫、衣料、裙褶、银饰、靴子七层几何；双向光流传播、循环两端锚定，再修正每帧遮挡、裙边和饰品位置。默认构建会重新生成结构，已有人工修改时使用对应编辑入口，避免先覆盖来源。
- **提示词要点**：姿态顺序与颜色严格对应、独立体积、背面不画隐形脸；X向画面右、Y向上、Z向观察者。完整形体参考与提示词见[candidates](art_source/ancient-canal/character-normals/candidates)。
- **产物与检查**：108张法线、108张银饰蒙版、四方向配对图集及可编辑层；检查颜色摘要、Alpha、尺寸、切片、时长、单位向量、全部相邻过渡和循环接缝。CPU联系图只检查来源，实际受光由第8步验证。

```sh
python3 tools/ancient_canal/build_character_normals.py
python3 tests/ancient_canal/check_normals.py
```

保留已编辑来源时，将上面的默认重建替换为二选一：几何JSON修订用 `python3 tools/ancient_canal/build_character_normals.py --use-geometry-edits`；七张手绘向量层修订用 `--use-painted-layers`。之后再运行配对检查。

### 6. 接入SpriteLamp空间受光

- **目的**：把逐帧法线与场景三维灯光连接，先校准方向，再判断人物效果，避免用整体调亮冒充法线有效。
- **输入与来源**：[SpriteLamp固定上游提交](https://github.com/winkidney/sprite-lamp-godot/tree/7b9e65958533c9f5d8146e77d1cf14d1f3b74706)、[本地快照与移植记录](art_source/ancient-canal/sprite-lamp-port/source.json)及[Godot空间材质接口](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)。快照记录该提交未附LICENSE／NOTICE，不虚构许可。
- **操作**：将法线强度、Y方向校准、灰材质和分档漫反射移植到空间切线基准；原生模式交给Godot，分档 `light()` 保留灯光衰减和阴影。方向／帧索引只算一次，同步颜色、法线、银饰蒙版；可见、法线和阴影共享世界竖直与主相机水平朝向。
- **提示词要点／工程约束**：先用球、法线平面与原生FIXED_Y材料检查零强度、Y校准和四向扫光；然后接入人物，保留最近邻、透明裁切、深度遮挡和脚底。此步不重新生成角色图。
- **产物与检查**：[原生材质](shaders/ancient_canal/sprite_native.gdshader)、[分档材质](shaders/ancient_canal/sprite_stepped.gdshader)及[校准夹具](tests/ancient_canal/calibration.gd)。灰材质单灯测试隔离其他光源；几何投影另行检查，高度图自阴影不在首版范围。

### 7. 集成场景、镜头和调试控制

- **目的**：让行走路线经过可测试的灯光，人物保持可读，同时能分别观察照明、法线、视差与景深。
- **输入与来源**：[布局](resources/ancient-canal/layout.json)、[参数定义](resources/ancient-canal/parameters.json)、[当前操作与镜头契约](docs/ancient-canal/README.md)。
- **操作**：主入口 `ancient_canal.tscn`，仅F／W固定朝向；跟随中心为脚底上方1.0125米，地图内部居中、外边缘逐轴限位。六层为近镇／远镇／近山／远山／近云／远云；6盏悬灯、6盏街灯及2盏大范围灯分组控制，自动路线经过冷暖光区。
- **提示词要点／工程约束**：不靠放大贴图或逐帧移动锚点补偿镜头；世界竖直、实际高度、碰撞和灯位保持一致。时段切换不覆盖镜头与景深，schema2仅主动保存，旧O配置校验后迁移为F／W。
- **产物与检查**：四页中文控制台、NPC／招牌交互、可取消路线与独立设置。用WASD、M、T、G、K检查操作，重点看移动、停止、桥面、码头和文本焦点。码头石纹／木纹交替来自同高顶面[Z-fighting](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html#depth-buffer-precision)：正式版隐藏DockFloor绘制、保留碰撞，灰盒仍可见；移动时验证修复。

### 8. 验证、录像和交付

- **目的**：分开核对数据、实际画面和性能，并把每项结论绑定到同一批源码与素材，防止沿用过期passed。
- **输入与来源**：[素材检查](tests/ancient_canal/check_sources.py)、[逻辑检查](tools/ancient_canal/validate.py)、[捕获入口](tools/ancient_canal/run.py)、[打包门槛与历史记录](docs/ancient-canal/production.md)。制作顺序先数据／逻辑，再GPU校准、四方向三循环、扫光、路线和人工视审，随后独立性能、录像与交付。
- **操作**：先完成下方无窗口检查，再从[指纹工具](tools/feature_fingerprint.py)冻结当前运行文件。GPU用最小化、不取焦点的X11与1920×1080离屏视口；每个输出选新目录。性能每时段预热至少5秒、采样至少30秒，不录制、读回截图或固定FPS，报告P50／P95／P99及设备；离屏结果不等于前台FPS。
- **提示词要点／工程约束**：视觉检查实际原图、连续动作和接缝，不从CPU图推断GPU通过。演示录像给角色特写、冷暖四方向、三时段、近／远景深和房屋侧面；结尾锁定角色、动画、机位、灯光与环境，只切法线ON／OFF／ON。
- **产物与检查**：保存当前指纹、原PNG、时序、报告和实际复审。编码保留观测墙钟VFR与漏采间隙，不插帧或宣称稳定30fps；独立解码数值审核后仍需人工查看画面。独立Linux包必须在空目录、全新设置下启动，不能只验工程运行。

`check_sources.py` 会调用法线检查并重写可编辑来源中的 `validation.json`，`--output` 只指定主报告位置；在独立复现副本运行并核对差异。

```sh
python3 tests/ancient_canal/check_sources.py --output "$RUN/source-check.json"
make test
python3 tools/ancient_canal/validate.py --mode all --output-dir "$RUN/cpu"
python3 tools/ancient_canal/validate.py --mode camera --output-dir "$RUN/camera"
python3 tools/ancient_canal/validate.py --mode regression --output-dir "$RUN/regression"
```

GPU脚本入口和输出参数见下表，统一传入 `--ignore-user-settings` 与当前 `--canal-fingerprint`，不要直接覆盖工具的历史默认目录：

| 检查 | 脚本 | 新输出参数 |
|---|---|---|
| 历史快速截图，需先适配当前F／W | `tools/ancient_canal/capture.gd` | `--canal-output` |
| 受光校准 | `tests/ancient_canal/calibration.gd` | `--canal-calibration-dir` |
| 三循环与扫光 | `tools/ancient_canal/capture_normals.gd` | `--canal-normal-capture-dir` |
| 真实路线 | `tools/ancient_canal/capture_route.gd` | `--canal-route-dir` |
| 竖直与切线 | `tests/ancient_canal/upright_validation.gd` | `--upright-output`，另加 `--upright-gpu` |
| 码头微动 | `tools/ancient_canal/capture_dock_stability.gd` | `--canal-dock-dir` |
| 三时段性能 | `tools/ancient_canal/benchmark.gd` | `--canal-output` |
| 特写演示 | `tools/ancient_canal/capture_lighting_demo.gd` | `--lighting-demo-output` |

旧 `capture.gd` 仍请求O镜头：当前控制器拒绝后，文件名 `lens-O.png` 实际对应前一次W状态，报告还保留固定的 `render/` 路径。先修正这些历史逻辑，再把快速截图用于当前完整验收。

例如录制完整特写演示并独立数值解码，在真实X11桌面终端执行，使用已安装引擎、全新输出和独立用户设置目录。下例已核对当前F／W源码接口，仍需本轮实际捕获与视觉复审后才能作为当前证据：

```sh
GODOT_BIN=$(python3 -c 'import sys; sys.path.insert(0,"tools"); from project import engine; print(engine())')
FINGERPRINT=$(python3 -c 'import sys; from pathlib import Path; sys.path.insert(0,"tools"); from feature_fingerprint import fingerprint; print(fingerprint(Path.cwd())["sha256"])')
export XDG_DATA_HOME="$PWD/$RUN/user-data"
export XDG_CONFIG_HOME="$PWD/$RUN/config"
export XDG_CACHE_HOME="$PWD/$RUN/cache"
"$GODOT_BIN" --path . --display-driver x11 --position 10000,10000 --audio-driver Dummy --disable-render-loop --script res://tools/ancient_canal/capture_lighting_demo.gd -- --ignore-user-settings --canal-fingerprint="$FINGERPRINT" --lighting-demo-output="res://$RUN/demo-render"
python3 tools/ancient_canal/encode_lighting_demo.py --mode all --producer "$RUN/demo-render/lighting-demo-report.json" --output-dir "$RUN/demo-video"
```

完整交付还有人工步骤：制作 `freeze-report.json`、全量 `source-hashes.json` 和独立 `source-review.json`，完成画面／录像／场景对照，以及启动与性能计数复核。仓库没有 `make freeze` 或自动签署这些复审的命令；字段和报告链按[组装器](tools/ancient_canal/finalize_evidence.py)与[打包器](tools/ancient_canal/package.py)核对，真实检查未完成时保留缺项。

打包器固定读取 `build/ancient-canal` 下的报告链；新目录的专项报告不会自动成为完整交付证据。在独立工程副本按消费端目录组织本轮报告，保留原始摘要与互指关系，再依次执行下列阶段；导出需要有效freeze，最终打包需要同指纹的accepted总报告：

```sh
python3 tools/ancient_canal/package.py export
python3 tools/ancient_canal/standalone_check.py
python3 tools/ancient_canal/encode_evidence.py
python3 tools/ancient_canal/audit_encoded_evidence.py
# 实际完成源图、解码录像与场景的独立视觉复审后
python3 tools/ancient_canal/finalize_evidence.py
python3 tools/ancient_canal/package.py package
```

交付为完整工程与制作来源、独立Linux包、截图／录像／原始性能证据及SHA256清单。当前F／W、居中跟随和主入口修订的无窗口记录与之前GPU、录像、运行包分开归因；历史性能和包不能作为当前完整验收。本Runbook仅整理已有流程，没有重新生成、录制或打包。

## 存档与参考

演进顺序为[驿站P6／P7](docs/validation/p6p7/README.md)与[P8视差／景深](docs/validation/p8/README.md)、[P9构图比较](docs/validation/p9/README.md)、[Frontal正面运河](docs/validation/p9-frontal/README.md)，再到当前江南河街。旧场景各自保留制作时的镜头、操作和验收范围。

在 Godot 中单独打开对应场景后按 F6，或运行其显式入口：

| 场景 | 用途 | 显式运行 |
|---|---|---|
| `scenes/waystation.tscn` | 原默认驿站，P6／P7／P8 视差与景深参考 | `make waystation-run` |
| `scenes/frontal_canal.tscn` | 历史正面运河，F／W／O 与镜距／FOV 比较 | `make frontal-run` |
| `scenes/reference_scene.tscn` | P9 A／B／C／D 四方案比较 | `make p9-run` |
| `scenes/reference_scene_graybox.tscn` | 历史参考场景灰盒 | 单独打开后 F6 |

历史场景保留各自的 P 视差、O 景深、C 镜头等操作，详见[存档场景操作](docs/operation/README.md)。历史回归与录像工具明确选择原场景，不随项目主入口变化。

`make visual`、`make record`、`make rebuild` 和 `make reproduce` 仍是历史驿站的验证与制作工具。江南制作来源、模型、贴图、法线及对应检查使用 [江南说明](docs/ancient-canal/README.md) 中的专用流程。

以下为历史驿站的实际 GPU 截图，保留用于参考：

![历史 P6/P7 驿站：晴昼步道](docs/validation/p6p7/captures/day-center-dof-on.png)

## 来源、验证与交付

原角色序列帧、帧序、每帧时长、透明轮廓和脚底锚点保持。角色来源见[默认角色接入](docs/validation/default-character/README.md)与[可编辑来源](art_source/characters/crescent-traveler/v1/README.md)。项目是原创 HD2D 技术与视觉样板，没有从原作提取素材；不包含战斗、背包或完整 RPG 系统。

江南 Linux 包使用 `jiangnan-river-street.x86_64`，默认进入古风场景。此前的驿站、Frontal 和江南运行包、录像、性能报告均对应各自制作时的版本。本次调整默认入口不重发历史包，也不将历史 GPU 证据标记为当前版本的验收。

运行需要支持 Forward+ 的显卡与 Vulkan 驱动。无窗口检查与实际 GPU 画面验收分开记录；工程检查通过不代表美术已获用户批准。当前测试与已知限制见[江南验收](docs/ancient-canal/acceptance.md)，历史报告见[完整文档索引](docs/README.md)。

[Plan：目标与阶段](Plan/README.md) · [ADR：决策及代价](ADR/README.md) · [领域模型](domain-model/README.md) · [来源与许可](NOTICE.md)

项目不自动提交、推送或发布。公开发布许可证由项目所有者决定，引擎及第三方许可按原声明保留。

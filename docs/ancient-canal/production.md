# 江南河街制作与复现

本文正文保留早期制作与交付记录，其中 F／W／O 镜头、10 盏可选灯、`waystation.tscn` 默认入口和 `7017…` 等运行指纹属于对应的历史版本。

当前项目默认启动 `ancient_canal.tscn`，仅使用 F／W 固定朝向与角色居中跟随，场景灯具为 6 盏悬挂灯笼、6 盏街灯和 2 个广范围光源，共 14 盏。完整复现顺序见[项目 README 的 runbook](../../README.md)，当前操作与验证范围见[江南河街说明](README.md)。后续入口和镜头调整以无窗口检查为主，正文中的截图、录像、性能与独立包结论仅适用于它们记录的版本。

用户选择 A“桥头酒肆”，再按实际 HD2D 相机、角色尺寸和可走通路调整构图。原 A／B／C 概念、修订、近景、提示词与来源保留在 `art_source/ancient-canal/concepts/2026-10-07`。概念中的人物只说明尺度与画风，运行角色原样复用已批准的 108 张颜色帧、帧序、每帧时长、待机索引和脚底锚点。四方向各 27 帧，每循环 1125 毫秒。

## 资产边界

| 输入／产物 | 位置与约束 |
|---|---|
| 原 A 角色颜色与时间线 | `assets/characters/crescent-traveler/v1`；108 个颜色 PNG 摘要保持不变 |
| 正面镜头、竖直人物 | 复用 F／W／O 镜头控制器；Ancient 专属空间材质使用世界 UP 与主相机水平朝向 |
| 颜色复用基点 | `art_source/ancient-canal/character-reuse.json`；颜色、图集、帧序、时长、脚底锚点 |
| 材质母图与结构 | `art_source/ancient-canal/textures`；内置 ImageGen 原 PNG、提示词、独立高度／结构 |
| 模型源与验证 | `art_source/ancient-canal/blender`；13 件 `.blend`、真实重开检查、独立 GLB 向量检查 |
| 运行模型与材质 | `assets/ancient-canal/models`、`textures`；GLB 内嵌图像，256 像素周期单元 |
| 角色法线制作源 | `art_source/ancient-canal/character-normals`；四方向六关键姿态、ImageGen 形体参考、108 帧结构层、双向运动场与修正 |
| 角色法线运行资源 | `assets/ancient-canal/character-normals/v1`；108 法线、108 银饰蒙版及配对图集 |
| NPC | `art_source/ancient-canal/npcs` 与 `assets/ancient-canal/npcs`；三次独立母图、结构、静态色图／法线／材质蒙版 |
| 字体 | `assets/ancient-canal/fonts`；随包中文字体、来源摘要与 OFL 原文 |
| 布局与参数 | `resources/ancient-canal/layout.json`、`parameters.json`；物理路线、地标、交互与中文参数定义 |
| 六层远景与灯具 | 近镇／远镇复用江南民居、柳树，山与云复用已有源资源；6 盏街灯新建几何、4 盏灯笼沿用现有布局 |

内置 ImageGen 不返回可复用随机 seed，生成来源明确记录 null。结构与程序生成使用各制作清单中的固定种子，不把程序种子冒称为 ImageGen 种子。母图只复制归档，原字节不重编码。

本轮镜头与站立修正不调用新的角色 ImageGen，也不重建角色颜色、法线、银饰或时间线。原概念、材质母图、NPC 母图及四方向形体参考的提示词、原 PNG 和调用凭据继续作为制作来源；增加街灯只使用可编辑程序几何和已有纹理。角色受光方向由空间基准修正，原逐帧向量数据保持不变。

## 离线制作重建

以下命令在工程根执行，使用项目已有的 Python、Pillow、NumPy、OpenCV、fontTools 与 Blender。制作时不安装插件，不启动 Blender 界面或服务。

```sh
python3 tools/ancient_canal/build_models.py --textures
blender --background -noaudio --factory-startup --disable-autoexec --python tools/ancient_canal/build_models.py -- --batch-exit
blender --background -noaudio --factory-startup --disable-autoexec --python tools/ancient_canal/build_models.py -- --verify-only --batch-exit
python3 tools/ancient_canal/build_models.py --verify-glb
python3 tools/ancient_canal/build_npcs.py
python3 tools/ancient_canal/build_character_normals.py
python3 tests/ancient_canal/check_normals.py
python3 tests/ancient_canal/check_sources.py
```

如果 Blender 的命令入口由 Snap 包装，可将 `blender` 替换为已安装包内的实际可执行文件。`--batch-exit` 仅用于已保存、重开并校验成功的后台任务，规避当前容器音频收尾阻塞；不改系统。原图已经随工程归档，离线重建无需重新请求 ImageGen。

模型按游戏米制与 Y 向上绘制，统一一次转换为 Blender 坐标再由 glTF 导出转回。酒肆、民居、格窗、檐口、船篷、拱桥底部与柳枝具有真实几何。模型按材质合并，三角化、UV 与切线随 GLB 导出，纹理打包进 `.blend` 与 GLB。

第 13 件模型为街灯：石座、木柱、金属箍、挑臂、斜撑及灯笼都有几何来源。6 个街灯实例各有独立灯光与柱体碰撞；2 盏默认投影，其他灯可独立开启。与 4 盏檐下灯笼合计 10 盏可选灯，主光和测试灯独立于这个目录。

码头正式木板面与物理地板顶面均为 Y=-0.32 米。物理辅助面在正式场景隐藏，灰盒中可见；右岸地面在下沉码头和接岸坡道处切开，避免正式木板与辅助面共面及岸面遮住坡道。船工原图、位置和脚底锚点保留。本轮 201 张实际 GPU 原图覆盖旧机位、F／W／O 四组微动及三组坡道移动／停止，均通过像素稳定检查与独立画面复审；报告保留原图摘要。

材质颜色从均匀照明的母图机械裁切和最近邻缩放，再用 128 像素象限镜像组成 256 周期单元。瓦槽、木纹、石缝、织物刺绣和叶脉单独绘制结构高度，按周期导数生成向量法线，颜色亮度不参与凹凸计算。左右、上下边界必须匹配，法线不能套颜色调色板。

角色逐方向保留第 0、6、13、20、26 帧及待机帧，下／上／左待机为 10，右为 11。ImageGen 给出体积参考，法线通过可编辑语义几何独立绘制，再由双向运动跟踪与逐帧修正传播。七层对应脸、头发、发辫、衣料、裙褶、银饰与靴子。只读颜色可用于运动匹配和遮挡区域判断，不用颜色亮度或 Sobel 推算法线。

编辑 `editable/<方向>/<帧>/geometry.json` 后使用 `build_character_normals.py --use-geometry-edits`；直接修改七张法线层后使用 `--use-painted-layers`。两种入口都重新归一化向量并保留原颜色 Alpha。修改后必须重新运行配对、时序、全部相邻过渡及循环接缝检查。

上述入口用于主动修订法线来源，本轮站立校正没有运行它们。新增 `tests/ancient_canal/upright_validation.gd` 只读校验原颜色／法线／银饰 SHA、实际 Sprite3D 网格、脚底向量和 108 组材质绑定。CPU 模式不执行 shader；GPU 模式提取生产材质的同一个 `upright_billboard_basis` 函数，在顶点阶段执行并从实际像素核对右／上／前和顶脚方向，保持原误差阈值。GPU 夹具的变量重名失败保留在 `build/ancient-canal/history-upright-fixture-uniform-collision`。

可见、法线和阴影使用相同基准：Y 为世界 UP，Z 为主相机朝向在 XZ 平面的投影，X 由正交叉乘确定；所有 pass 使用主相机而非阴影相机。保持模型平移与脚底锚点，不旋转碰撞体。原生校准面使用 `BILLBOARD_FIXED_Y`，四向扫光使用水平右／前和世界 UP，截图 ROI 投影真实 sprite 的全部网格顶点。

F／W／O 的镜距与 FOV、六层视差各有独立控制器。自然模式保持源世界位置；艺术模式按参考点的水平投影补偿，其同层其他深度是透视近似。远景根节点可移动，物理岸面、水域阻挡、桥和码头保持世界位置。

schema 2 设置将普通材质／照明／环境参数、当前镜头方案与跟随、F／W／O 三组镜距和 FOV、六层视差、单灯覆盖及远景最后时段作为一个候选，完整验证后统一应用。照明变成自定义后，远景仍恢复最后的晴昼／黄昏／夜晚调色。旧 schema 1 只在内存迁移有效非镜头字段，镜头与视差改用新默认；显式保存前原文件保留。单灯隔离与法线比较保存进入前的候选、实际镜头姿态与远景状态，退出恢复；临时模式内的保存也写入进入前的候选。隔离期间阻止普通照明／时段调节和解除固定状态，所选灯的5字段仍可调整。

## 验收与打包门槛

素材检查只证明数据来源与配对。实际场景由新的无窗口逻辑测试、最小化不取焦点的 GPU 截图、四方向三循环／扫光／灰材质录像、路线与输入测试、参数与跨进程设置、旧场景回归、独立包运行共同证明。三时段性能使用实际 1920×1080 视口，预热后每段至少 30 秒墙钟采样。离屏截图的强制绘制或固定帧录制不能充当实时 FPS。

灰材质四向扫光关闭测试灯投影阴影、主光、灯笼与街灯，仅保留测试灯和少量白色环境补光，避免其他灯或几何阴影干扰待测法线。常规场景的主光、灯笼、街灯和测试灯阴影可调，遮挡、投影和三时段效果单独检查。四页控制台共有 68 个场景字段和 5 个单灯字段；自动路线由 G 或顶部按钮开始，Esc 或移动键取消。

性能采样与截图、录像分开。离屏实时采样虽使用真实 GPU 和实际墙钟，也不包括前台 present、桌面合成或显示同步耗时；报告应注明设备、视口、预热、采样时长及离屏窗口条件，不能把该结果称为前台交互性能。每个样本须有唯一且配对的 pre／post 绘制序号，并核对强制绘制与主循环资源处理绘制请求；`Engine.get_frames_drawn()` 不计直接强制绘制，不能单独作为总数。post 回调也不是 GPU 完成栅栏。当前三时段各预热至少5秒、采样至少30秒，P95晴昼7.338／黄昏7.384／夜晚7.339毫秒，此离屏条件的60FPS目标通过。设备为NVIDIA GeForce RTX 4070 SUPER，原始唯一pre／post序号和全量间隔留在performance目录。分项结果见[验收清单](acceptance.md)，完整交付以最终报告和实际包清单为准。

旧指纹 `98b4b65c12ac1639144f6fcd7036ba97f338748b277262d3e02ae2ee442d2c62` 的十四项通过记录、九段录像、逐帧复审、性能原始采样及旧 Linux 包保存在 `build/ancient-canal/history-before-frontal-upright-20261007`。它们属于调整前的相机、55 参数、12 模型版本。本轮必须重新冻结资源并完成对应范围的当前验收，不把历史 passed 复制到新报告。完整源库存、独立源审查、当前录像数量、实际复审和性能数据均以本轮报告为准；交付包成功状态只由 `delivery/delivery-report.json` 证明。

先完成本轮真实 GPU 捕获、逻辑与交互检查、三时段性能测量，冻结运行资源；录像编码和独立包检查按以下顺序执行。实际 GPU 检查须使用既定最小化、不取焦点方案：

```sh
python3 tools/ancient_canal/package.py export
python3 tools/ancient_canal/standalone_check.py
python3 tools/ancient_canal/encode_evidence.py
```

编码结束后，对实际逐帧图像、路线代表画面、本轮编码录像和选定概念与场景进行独立视觉复审，分别保存当前指纹的 `visual-review.json`、`route-visual-review.json`、`video-review.json` 和 `scene-comparison.json`。编码录像还须保留独立的 `video-chain-audit.json`、`video-decode-audit.json` 及实际查看的解码联系图。这些报告必须来自真实完成的画面检查，不能仅执行命令或填入 passed 代替复审。最后完成全量源核对、完整可移植源路径库存 `source-hashes.json` 和独立三项范围审查 `source-review.json`，再组装最终报告和交付包：

```sh
python3 tests/ancient_canal/check_sources.py
python3 tools/ancient_canal/finalize_evidence.py
python3 tools/ancient_canal/package.py package
```

`export` 先核对当前运行指纹和 `build/ancient-canal/freeze-report.json`，校验匹配引擎的模板摘要，建立没有 `.godot` 缓存的新 staging 工程。仅在 staging 修改启动场景为 `scenes/ancient_canal.tscn` 和 JSON 导出规则，原工程 `project.godot` 的 `scenes/waystation.tscn` 入口保持。导出的 ELF、引擎版本、模板与源码指纹写入 `export-report.json`；它只证明导出成功，独立启动仍需后续验收。

`standalone_check` 把 ELF 单独复制到空临时目录，用全新 XDG 数据目录运行。它不传入工程、脚本或场景路径，检查嵌入包默认进入江南河街，并实际加载 108 组颜色／法线／蒙版、13 件模型、三名 NPC、六层远景资源、10 盏可选灯、字体与四页 68+5 控制字段。无窗口逻辑检查和最小化无焦点的真实 GPU 截图均通过，才写入 `standalone-report.json`；它不替代路线、动画连续性或实时性能验收。

`encode_evidence` 只编码已有真实 GPU PNG：角色保留原 41／42 毫秒时序，路线使用观测墙钟 VFR，并记录捕获报告、时序报告、concat 清单和实际 MP4 packet 验证。它写入 `video-report.json`，不生成新的 GPU 通过结论，也不执行视觉复审。路线漏采样保留为真实时间间隙，不补造画面或宣称完整 30 FPS。

`finalize_evidence` 只组装已经通过且指纹一致的 sources、headless、input_regression、gpu、video、performance、settings、standalone 报告和四份独立视觉复审，缺少任何一项即拒绝。它不生成视觉通过结论；组装成功才写入 accepted 的 `final-report.json`，随后才能打包。

`package` 要求 `build/ancient-canal/final-report.json` 的 passed 为 true、status 为 accepted，运行指纹等于当前源码。它检查 sources、headless、input_regression、gpu、video、performance、settings、standalone 八类报告及摘要，还核对全部需求 scope 与证据路径。截图和录像从本轮报告指向的原文件读取，必须为原生 1080p；三时段分位数从原始 frame_intervals_ms 重算，并核对唯一 pre／post 序号、绘制计数、预热、无固定 FPS 和无读回条件。旧截图、CPU 预览或过期指纹不能通过打包门。

视频另核对捕获报告、时序报告与 concat 清单的摘要和互指关系，逐包读取 MP4 的实际时间戳与时长，核对原 PNG 序列及总时长。三类制作证据自动进入证据包；原 PNG 帧需保留到打包核对结束，首版证据包不全量复制录制用 PNG。

最终报告十九项需求必须有 passed、scope 和 evidence。范围包括 sources、models、character_normals、calibration、visual_loops、light_sweeps、scene_comparison、interaction、input_safety、parameters、settings、old_regression、gpu_performance、standalone、camera_profiles、upright_sprites、distant_scenery、streetlights、dock_stability。未完成项保持失败或缺失，不能通过缩小字段集合获得完整交付。

本轮运行指纹为 `7017e0965120c3dad392a9b35f2002bad6e6eccdef2c6ae63485da1d0e13f8cd`。当前无窗口场景2204项、站立CPU825项／GPU940项及56个实际像素样本通过；8张原生受光校准原图、648张角色源PNG的36张有序／接缝／开关联系图均已实际查看。场景另有20张原生1080p截图、码头201张原图。当前九段MP4严格核对原PNG的producer SHA，八段角色各81帧／3375ms；路线332帧按20.59436秒观测墙钟编码，精确时间基后的时长20599ms。618个目标采样槽中286个因写图背压漏采，录像保留这些间隔；980帧独立解码及41张联系图、19张原生解码关键图的实际查看复审通过，记录在video-review。

当前ELF大小106469432字节，SHA256 `5684770a19fe3da9e26dab1a8074995b0025a427dc3e85368eae78b1db5f6391`；空目录、全新XDG、无显式场景参数下的无窗口与真实1080p GPU启动分别通过。当前source-check的8项检查与1738个文件子集通过，包括13件模型真实重开及UV／切线、7组材质平铺、108帧严格配对法线。完整源库存、独立源审查和十九项总accepted报告在全部文档／工具冻结后生成并核对；不能仅因ELF启动或视频编码成功发布交付结论。

源工程包保存完整制作链和 SHA256 清单；Linux 包保存独立 ELF、中文说明与许可；证据包保存明确归因的 JSON、截图、录像和性能原始采样。排除 `.godot`、构建缓存、主机日志、系统库、研究截图及父目录内容。运行无需其他仓库或制作服务。本轮不自动提交、推送或发布。

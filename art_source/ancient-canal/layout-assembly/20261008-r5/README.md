# Ancient R5 可编辑总装

[ancient-r5.blend](ancient-r5.blend)包含按 R5 施工图摆放的房屋、酒肆、三摊、低桥、前岸码头、小船、五名 NPC、两岸柳树、两层背景房屋和树木，以及十四个灯位。建筑保留集合实例，纹理打包在文件中。

采用 Godot `(X,Y,Z)` 到 Blender `(X,−Z,Y)` 的坐标转换，一米对应一米。各实例保留 Godot 原始位置和资源 ID。总装的点灯能量仅供建模预览，真实照明以运行场景参数、灯组和单灯覆盖值为准；天空、山云层和相机视差仍由 Godot 控制。

来源为项目现有江南 GLB；低桥使用另存的 `bridge_low.glb`，保留原桥和全部资源来源。`base-layout.json` 是应用 R5 前的运行布局快照。[construction-recipe.json](construction-recipe.json)记录图纸与运行布局校验值，[assembly-manifest.json](assembly-manifest.json)记录可编辑模型的校验值和实例坐标。

重建：先运行 `python3 tools/ancient_canal/build_layout.py --apply`，再运行 `blender --background --factory-startup --threads 1 --disable-autoexec --python tools/ancient_canal/build_layout_assembly.py`。默认使用 R5 固定输出目录，已有验收文件应先另存新版本。运行场景使用三组地面网格，并从同一矩形分区生成物理碰撞；码头与坡道处切出地面，避免共面重叠。

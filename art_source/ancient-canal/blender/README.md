# 江南三维模型来源

模型由 `tools/ancient_canal/build_models.py` 制作，固定结构 seed 20261007。输入是江南材质清单与已选 A 概念。建筑、侧墙、曲面屋顶、瓦垄、格窗、栏杆、船篷、拱桥内侧和柳枝均有真实几何，不使用概念画面作为立面。

模型 `tavern`、`house`、`bridge`、`cloth_stall`、`food_stall`、`bank_wall`、`dock`、`boat`、`lantern`、`wine_jar`、`cloth_banner`、`willow` 各有可编辑 `.blend` 和独立 GLB。全部图像打包在 Blender 文件及 GLB，运行包不需要 Blender、其他仓库或在线生成服务。

尺寸按游戏米制、Y 向上绘制，`xyz()` 一次转换为 Blender Z 向上，glTF 官方导出选项将其转换回 Y 向上。正面朝 +Z。桥面跨 X 轴，范围 -4.2 到 4.2 米，宽 2.8 米，顶面为 `1.3 * (1 - (x/4.2)^2)`，桥底是连续可见的实体拱形。

模型按材质合并以限制绘制次数，所有面三角化并生成 UV 与切线。木料、屋瓦、墙石和织物使用各自周期纹理与切线法线。色图使用最近邻，法线节点设置为线性数据；金属、陶器与灯笼纸另有独立粗糙度及发光参数。

重建及重开检查在工程根运行：

```sh
blender --background -noaudio --factory-startup --disable-autoexec --python tools/ancient_canal/build_models.py -- --batch-exit
blender --background -noaudio --factory-startup --disable-autoexec --python tools/ancient_canal/build_models.py -- --verify-only --batch-exit
python3 tools/ancient_canal/build_models.py --verify-glb
```

`--batch-exit` 只用于后台制作，所有保存、重开和校验完成后退出。它规避当前容器中 PulseAudio 收尾阻塞，不改系统设置。导出期间桌面缩略图缓存不可写的提示不影响已保存模型或纹理。失败的向量校验必须修正，不能忽略。

`manifest.json` 记录每件模型的真实范围、顶点/三角数、材质合并数及摘要。`geometry-validation.json` 从独立 GLB 字节解码检查 UV、向量、切线正交、采样与内嵌图片。`tavern-construction-preview.png` 是 CPU 建构检查，不作为 Godot GPU 场景验收证据。

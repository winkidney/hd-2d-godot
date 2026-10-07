# A 角色逐帧法线来源

默认角色沿用既有四方向 108 张 256×256 颜色帧。法线制作始终只读颜色与动画清单，构建前逐文件核对[复用基点](../character-reuse.json)的摘要。脚底锚点为 `[128,240]`，待机帧为下、上、左方向的第 10 帧和右方向的第 11 帧。

## 形体与运动

四个方向分别使用原第 `0、6、13、20、26` 帧和待机帧制作[关键姿态板](reference)。内置 ImageGen 给出六姿态的体积构造参考，原图、提示词和调用来源保存在 [candidates](candidates)。生成模型未提供可指定种子，来源中记录为 `null`。参考图用于判断脸、发束、编辫、月冠、裙褶的体积，不裁切、缩放或采样进运行法线。

[制作脚本](../../../tools/ancient_canal/build_character_normals.py)逐方向绘制独立椭球、曲线柱体、辫节、扇形裙褶与银饰体积。法线直接来自这些几何面的方向。颜色 RGB 只用于运动匹配及材质遮挡边界，不作为高度、坡度或凹凸来源，不使用漫反射亮度梯度或 Sobel 法线。

Farneback 运动场在 [motion](motion) 保存原精度计算结果的 float16 压缩副本。几何标记分别沿正、反时间追踪，闭环两端都锚定原第 0 帧，再混合两条轨迹。每帧校正暴露的脸、手、银饰位置；裙边粉红刺绣即使与皮肤共享颜色，也不会变成皮肤体积。交叉步伐的靴子以当前可见形状的主轴修正，避免受光形体留在上一只脚的位置。

每帧的 [editable](editable) 文件夹包含几何 JSON、语义标签，以及脸、头发、发辫、衣料、裙褶、银饰、靴子七张独立法线层。层的透明区互不重叠，合成后透明轮廓等于原帧。六组 [keyposes](keyposes) 单独保留几何构造；[corrections](corrections)记录全部帧的局部修正。

## 运行资源与编辑

[运行清单](../../../assets/ancient-canal/character-normals/v1/manifest.json)提供 108 张法线、108 张银饰蒙版和每方向的配对图集。图集完全复用颜色区域、留边与透明轮廓；同一帧索引即可读取三种材质数据。

RGB 按 `normal × 0.5 + 0.5` 编码，X 向画面右，Y 向画面上，Z 向观察者。法线与蒙版使用线性数据、最近邻采样，无调色板、抖动或 mipmap。银饰蒙版白色为银饰，黑色为衣料等其他材质，alpha 仍等于颜色轮廓。法线不得作为 sRGB 颜色纹理读取。

重建全部来源：

```sh
python3 tools/ancient_canal/build_character_normals.py
python3 tests/ancient_canal/check_normals.py
```

修改 `editable/<方向>/<帧>/geometry.json` 后，以 `--use-geometry-edits` 重建并保留逐帧标记。直接绘制对应七张法线层后，使用 `--use-painted-layers` 合成。绘图应保持原 alpha 与层覆盖范围；合成会重新归一化向量。运行 PNG 不用于反向改色或修改原动画。

## 复核与修订

第一版全局皮肤材料识别把少数粉红刺绣作为皮肤，已改为随姿态移动的脸、颈及手部区域约束。第一版单向追踪在左右行走的循环接缝有积累漂移，已改为闭环双向追踪。交叉步伐部分靴子离开原曲线标记，已加入逐帧可见靴子形体修正。

[修订记录](revision-history.json)保存各版问题与已经测得的接缝差异，初版两张放大审查图放在 `revisions/initial-review`，不能作为当前法线使用。除六关键姿态外，[下](review/down-all-27-clay.png)、[上](review/up-all-27-clay.png)、[左](review/left-all-27-clay.png)、[右](review/right-all-27-clay.png)各 27 帧灰材质联系图补齐所有中间动作的来源审查。

[向量与配对校验](validation.json)重新读取全部颜色、法线、蒙版、图集和可编辑层，核对原颜色摘要、时序、alpha、单位向量、图集切片与全部 27 个相邻过渡，包括循环接缝。CPU 灰材质图和三循环扫光只辅助检查来源，不能代替实际 Godot 灯光、遮挡或 GPU 验收。

| 方向 | 六姿态颜色／法线／银饰／灰材质 | 三循环扫光 |
|---|---|---|
| 下 | [关键姿态](review/down-key-gallery.png) | [动画](review/down-three-loops.gif) |
| 上 | [关键姿态](review/up-key-gallery.png) | [动画](review/up-three-loops.gif) |
| 左 | [关键姿态](review/left-key-gallery.png) | [动画](review/left-three-loops.gif) |
| 右 | [关键姿态](review/right-key-gallery.png) | [动画](review/right-three-loops.gif) |

# 江南材质来源

`mother-sheet.png` 与 `tavern-detail-reference.png` 是内置 ImageGen 的两次独立生成原图，原字节保留。提示词分别在 `prompt.txt`、`detail-prompt.txt`；参考是已选概念 A。内置工具不提供 seed，因此清单记录 null。第二张只用于屋瓦、木格窗、斗拱与檐口造型对照，没有作为模型立面贴片使用。

运行材质位于 `assets/ancient-canal/textures`，统一为 256×256，名称为 `roof`、`wood`、`stone`、`plaster`、`indigo`、`red`、`leaf`。颜色名为 `材料.png`，法线名为 `材料_normal.png`。

前六种颜色从材质母图对应格裁切，最近邻缩放，取 128 像素象限镜像拼成 256 像素周期单元。像素块和色组来自母图。叶片用石面单元的像素变化重新赋予绿色，转换参数与摘要保留在清单。

每种材料有可编辑 `材料-structure.json` 与独立 `材料-height.png`。瓦槽、搭接、木板缝、木纹、石缝、织物刺绣、叶脉由结构坐标绘制；不从颜色明暗推算高度。法线是周期高度结构的向量导数，采用 OpenGL 切线空间，X 向右、Y 向上、Z 朝外。没有法线调色板、抖色或有损颜色压缩。

`manifest.json` 保存来源原图、生成调用数、处理参数、尺寸、周期边界和颜色/法线摘要。各单元左右、上下边界像素严格一致。结构内的微细凹凸用于动态受光，颜色图不加入投影阴影。

重建方法在工程根运行：

```sh
python3 tools/ancient_canal/build_models.py --textures
```

这一步需要项目已有的 Pillow 与 NumPy。运行包使用已完成贴图，不依赖这些制作工具。

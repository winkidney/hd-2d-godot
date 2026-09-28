# ADR-08 · Blender 与图像素材管线

状态：Accepted

## 背景
交付必须包含可编辑来源，不仅最终截图。

## 决定
Blender Python 生成模块化模型，保存 .blend，显式导出 GLB；程序化原创像素图集为首轮基线；ImageGen 替换须归档原图。

## 备选方案
只保存 GLB；直接导入 blend；一次生成整张未知规格图集。

## 代价与限制
重建依赖 Blender/Pillow；运行仅需 Godot/已导出资源。

## 验证与复议条件
实际重新打开 blend；资源 SHA-256 清单；处理脚本可重跑。
更改上述约束时必须更新本 ADR 或新增 superseding ADR；测试通过不自动代表用户视觉接受。

参考：[官方资料](../docs/research/README.md)。

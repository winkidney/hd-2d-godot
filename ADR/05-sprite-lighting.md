# ADR-05 · 角色受光、透明与落地

状态：Accepted

## 背景
普通半透明会排序错误；默认 Sprite3D 不受光。

## 决定
shaded=true；alpha-cut discard；开启深度测试；单主相机 billboard；接触阴影。首轮不依赖 AI 法线。

## 备选方案
无光照贴片；Alpha blend；强法线塑料化。

## 代价与限制
裁切边缘较硬；Billboard 投影不是体积角色真实阴影。

## 验证与复议条件
遮挡/受光截图；明确自阴影与侧厚度限制。
更改上述约束时必须更新本 ADR 或新增 superseding ADR；测试通过不自动代表用户视觉接受。

参考：[官方资料](../docs/research/README.md)。

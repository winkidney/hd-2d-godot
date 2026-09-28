# P9 · 水城场景领域模型

状态：实施中；领域约束为验收规范，不是已完成证明。

| 模型 | 责任 | 不负责 |
|---|---|---|
| ReferenceScene | 组合新世界，复用Waystation实验流程 | 改写旧地图或原默认参数 |
| ReferenceLayout | 建筑/平台/路段/坡道/灯具/NPC坐标及新相机 | 每帧背景偏移 |
| ModuleRecipe | Blender尺寸、UV、枢轴、模型输入输出散列 | 隐式依赖宿主绝对路径 |
| GeneratedIntake | ImageGen资源板的归一化裁切输入与原始来源记录 | 重新生图必定得到同像素 |
| PixelRecipe | 清边、周期化、调色、帧锚点与有限动画规则 | 声称派生动画为完整AI动画 |
| WalkSurface | 平台/坡面可走区域；可见楼梯独立 | 通过传送越过碰撞 |
| Landmark | 原图归一化位置及三维拟合点 | 证明不可见结构与原作一致 |
| UrbanBackdrop | 三层城市剪影及独立云根 | 改变地面碰撞或人物输入 |
| SceneExperiment | 共享P6/P8控制器，独立布局ID和存储路径 | 重置旧场景个人设置 |
| ReferenceValidation | 路径、截图、原始计时、构建指纹、独立包 | 代替用户美术批准 |

## 不变量
新场景名称/布局/偏好独立，默认旧场景启动行为不变。
世界Y向上，单位米；Blender轴转换仅一次；48×64角色统一脚底，不移动碰撞体伪造动画。
三维桥拱不能被实体方块填住；河道不得成为隐藏可走平面。
楼梯连续坡面仅覆盖踏步宽度与水平长度，角色上下坡实际走通。
视差只作用装饰远景，近场建筑、人物、道路、碰撞不补偿。
时段和F3/F5/F6/F8语义沿用旧场景；配置保存只改本机新场景文件。

## 流程
用户参考/已批准ImageGen → intake+来源 → 像素资产 → Blender模块 → Layout烘焙 → ReferenceScene → 实验参数 → GPU/路线/交付验证。
[计划](../Plan/features/reference-scene-rebuild.md) · [重建ADR](../ADR/17-reference-scene-reconstruction.md) · [美术ADR](../ADR/18-generated-art-asset-pipeline.md)。

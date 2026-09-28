# 领域模型扩展：远景、步道、相机与景深

## 对象与责任
| 对象 | 状态与输入 | 输出／约束 |
|---|---|---|
| CameraRig | home、target、gain、dead_zone、max_offset、smoothing、follow、frozen | 每帧最终相机姿态；同步平移目标与位置 |
| WalkwayDefinition | center、direction、length、width | 烘焙道路与碰撞；direction 为水平单位向量，建造后不随相机旋转 |
| BackgroundRig | 背景 GLB、云图、配色 JSON、cloud_time、wind_enabled | 固定山体与移动云；不拥有玩家或相机 |
| LightingPreset | day / dusk / night、太阳／补光／灯／雾／水 | 原子时段事件；同步背景但不重置景深 |
| DofProfile | amount、near_clear、far_clear、transitions、focus_speed | 单相机资源副本；不直接写入原始 .tres |
| DofController | 最终相机、人物中心、场景锚点、模式及用户选择 | 正确相机深度下的原生双端景深 |
| ValidationRun | 版本、指纹、路线点、投影、图像、时间序列 | 分离数值证明、真实渲染与美术批准 |

## 每帧顺序
物理输入 → PixelActor 移动 → CameraRig 更新最终姿态 → DofController 计算深度 → 背景风时间 → 渲染 → 捕获／计时。
山体不需要每帧依据相机更新位置；天然视差来自固定几何与移动相机。

## 不变量
1. 正常探索跟随默认开启。死区、路径端点可短时不动，但主路段必须有持续相机平移。
2. 横向步道与原桥连通，角色仍自由二维平面移动，不自动牵引，不用传送完成路线验收。
3. 世界采用 Y 向上；相机深度取 -view.z；云的独立移动不得被记为山体视差。
4. DOF 实际开关 = 用户总开关 AND 单端选择 AND 全局 FX 开关。时段切换不改任何用户选择。
5. near_distance < far_distance；过渡距离 > 0；protected 焦点在清晰区内保持稳定，超界平滑响应。
6. HUD 不模糊。调参面板显示时阻止角色移动；Esc 先关闭面板，不退出应用。
7. 背景无碰撞，纯边界碰撞不等于可见遮挡。射线检查与卡片遮挡截图都要保留。
8. 运行资源改动后旧验收指纹失效；发布必须匹配当前资源和已验收二进制散列。

实现导航：[ADR-14](../ADR/14-native-dof-control.md)、[ADR-15](../ADR/15-open-world-background.md)、[P7](../Plan/features/distant-background-parallax.md)。

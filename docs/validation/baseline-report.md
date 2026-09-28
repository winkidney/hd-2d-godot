# 2026-09-28 可运行基线验收

当前结论：工程与真实 GPU 基线已跑通；最终风格认可仍待用户 Review。不是原作渲染参数的等价性证明，也不把程序化美术声明为已获批准的正式美术。

## 实测环境
Godot 4.7.2.stable.official.ed1daf0bf；Blender 5.2.2 LTS；Python 3.14.4；Pillow 11.3.0；Fedora 43 KDE；RTX 4070 SUPER；NVIDIA 驱动 580.142。GPU 输出 1920×1080，Forward+，Vulkan，单一主视口。

## 已记录的验收
源码 headless 执行 22 项功能断言：两方向过桥、河岸/护栏/建筑碰撞、对话范围/输入锁、预设身份保持、绑定与后处理切换等。真实 GPU 执行 28 项，包括四张截图和两组实际绘制帧/GPU 计时有效性检查。
独立 Linux 可执行文件另复制到不含项目资源的目录，分别通过 22 项 headless 与 28 项 GPU 检查，证明嵌入资源可运行；日志不能代替其他硬件兼容性测试。

## 性能样本
每预设预热至少 120 个实际绘制帧，再采样 360 帧；关闭应用 VSync，固定镜头，HUD 隐藏。下面是首轮归档，不是跨机器保证。

| 预设 | 完成绘制帧间隔 P95 | 视口 GPU 时间 P95 | 实际采样绘制帧 |
|---|---:|---:|---:|
| 黄昏 | 1.847 ms | 1.092 ms | 360 |
| 夜晚 | 1.711 ms | 1.086 ms | 360 |

该固定机位样本低于 60 FPS 的 16.667 ms 帧预算。样本时间较短；不能推断长时间运行、复杂新关卡或其他显卡持续性能。frame_post_draw 间隔不是孤立 GPU 时间，GPU 数值另由引擎视口时间戳测量。原始样本与全部断言在 [GPU 报告](evidence/gpu-report.json)。

## 图像证据
[黄昏](../media/dusk.png) · [夜晚](../media/night.png) · [带 HUD](../media/dusk-hud.png) · [夜晚无后处理](../media/night-no-effects.png)。均为远端真实 Godot 渲染，不是概念图。
已实际检查屋顶、主场景、角色、桥梁和灯光对照；单张截图不能完整验证所有角度的透明遮挡或移动闪烁，用户仍应按操作手册走一遍。

## 已修复问题
屋顶内向绕序导致缺面，已在 Blender 生成器修复并重建；静态烘焙保留重复导入实例导致退出资源泄漏，已按 ADR 12 扁平化，复跑无先前 ERROR；水面法线从错误空间改为视图空间；测试工具会检查日志而不只看退出码。

## 静态、重建与独立包证据
70 项静态检查已通过，包含 14 张源图散列/规格、内存再生成、GLB 与 blend 源对应、Python 语法、文档链接和常见私有路径检查。结果见 [静态报告](evidence/static-report.json)。
[无图形功能报告](evidence/headless-report.json)与[独立包报告](evidence/standalone-report.json)分别证明源码行为与嵌入资源包可运行；独立包详细 GPU 报告见 [standalone GPU](evidence/standalone-gpu-report.json)。
[干净重建报告](evidence/reproduction-report.json)记录 assets/models/import/bake/test 五步；保留的 `build/` 日志是本地排障材料，不纳入源码包。
`build/delivery/SHA256SUMS` 校验最终归档；源码包内还有 `SOURCE_SHA256.json`。归档散列不是美术质量评分。

## 复跑与条件
执行 `make test`、`make visual`、`make reproduce`；重新导出后执行 `make verify-release`，通过后再 `make package`。更新基线证据需说明版本/参数变化，不能用新图悄悄覆盖旧报告结论。
本轮尚未实施长时间稳定性、不同 GPU/系统、所有镜头角度以及外部输入设备测试。F12 路由由同一 capture 函数实现，自动截图测试不等于已模拟操作系统键盘设备的端到端测试。

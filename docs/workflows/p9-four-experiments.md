# P9 四方案复现与审阅

本轮从检查点 `3b6333f` 继续，保留历史 `build/p9`、旧素材和旧场景。新证据在 `build/p9-experiments`，不覆盖旧轮次。全部命令在工程根目录执行；工具来自已安装环境，不自动安装或联网。

## 生产与验证顺序

```sh
python3 tools/p9/process_assets.py
blender --background --factory-startup --disable-autoexec --python tools/p9/build_models.py
make p9x-import
make p9x-atlas
make p9x-test
make test
make p9x-quick
make p9x-visual
make p9x-record
make p9x-export
make p9x-rebuild
make p9x-package
```

`p9x-atlas`、`p9x-quick`、`p9x-visual`、录像和独立包 GPU 验证需要真实桌面 GPU。测性能时不要同时执行其他 GPU 作业。性能按四方案 × 三时段各 30 秒采样，关闭垂直同步；记录渲染完成帧间隔、Godot viewport GPU 时间及引擎报告显存。它不等同显示器呈现延迟，也不是系统总显存监控。

原图配方保存在 `art_source/reference-scene/manifests/intake.json`。模型脚本保留 `.blend` 和 `.glb`，图集脚本从同一 palazzo 模型离线渲染七角度 × 三时段。素材板参与生产，延伸概念图仅用于构图；原游戏研究截图不参与采样，也不进入分发源码包。

## 对照规则

机制截图固定玩家三个观察点，关闭景深并冻结水面、风和时间。完整截图另启景深。四段录像使用同一路线、同一速度、同一时段切换表；不通过瞬移跨越路线，只有录像开始将角色放回共同出生点。四宫格只对视频做等比缩放和拼接，不重计时、不改变某一方案速度。

角色高度按真正朝向镜头的 Sprite3D 四边形端点校准，不能用竖直世界线段替代。B/C 的 GPU 标记增加 `−6/0/+6°`，所以不继续套用旧 P8 固定朝向透视公式；旧场景原标记测试仍单独保留。

测试源码修改会改变运行证据指纹。交付前应重跑源码 GPU 和独立包；`package` 拒绝过期的源码 GPU 证据。

## 审阅入口

运行 Linux 二进制，按 F9 切换 A/B/C/D。F6 景深，F8 视差，WASD／方向键行走，E 交互，T 切时段。面板可运行共同路线，期间键盘被隔离，Esc 可取消。切换不更改人物、碰撞和时段；每个方案保留自己的参数。

最终结论见 `docs/validation/p9-experiments/README.md`。技术通过不等于美术达到原作质量或用户已选定方案。全部方案保留，不替换 C/D 的方法以掩盖限制。

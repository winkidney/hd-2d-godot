# 交付、依赖与复现

## 独立 Linux 包
`make export` 输出 `build/linux/waystation.x86_64`，运行资源嵌入可执行文件；目标为 Linux x86_64、桌面 Forward+。在其他 Linux 发行版、GPU 或驱动上运行仍需另行验证。
`python3 tools/verify_release.py` 将该文件复制到独立目录，不复制项目资源，分别执行 headless 功能测试和 1920×1080 GPU 验收。报告在 `build/validation/standalone-report.json`，包含被测二进制散列；源码测试不能代替这个步骤。
执行 `make package` 前，需要 `make test`、`make reproduce` 和当前二进制的独立运行验收通过。打包器检查报告与二进制散列，拒绝把未验证的新文件当作已验证包。

## 归档内容
`build/delivery/hd-2d-waystation-linux-x86_64.zip` 是运行包；`hd-2d-godot-source.zip` 是带原始素材、Blender 源文件、脚本、测试、Plan/ADR/domain-model 和文档的源包。源包内 `SOURCE_SHA256.json` 记录文件散列。
运行包不带 Godot 编辑器或 Blender。`SHA256SUMS` 校验归档本身；源包不包含 `.godot/`、模板压缩包、临时日志、虚拟环境或 Blender 自动备份。
录制完成且转换为 MP4 后，打包器同时复制 `waystation-preview.mp4`。演示是离线 MovieWriter 实际渲染，不能用编码速度推断实时性能。

## 干净重建
`make reproduce` 创建新的项目副本，不复制缓存或 build，重新生成 14 张 PNG、运行 Blender 保存与 GLB 导出、Godot 导入、烘焙并跑全部静态与 headless 功能测试。副本及分步日志留在 `build/reproduction/`，汇总在 `build/validation/reproduction-report.json`。
PNG 在固定工具版本下应精确匹配散列；`.blend` 和 Godot 烘焙文件可能带内部 ID/元数据，不承诺逐字节相同，而验证来源、结构、导入与行为。实际 GPU 是独立验收，不由重建命令推断。

## 模板与安全
`make templates` 先校验现有项目内模板；缺失时才从锁定的 Godot 官方 HTTPS 发布下载约 1.28 GB 压缩包并核验 SHA-256，只提取白名单的 Linux 模板。不会使用 sudo、全局安装、下载即执行的 Shell 或监听服务。
`dependencies.lock.json` 记录引擎、Blender、Python、Pillow 与模板散列。已有环境满足重建要求；Blender MCP 仍未安装，属于单独审批项。`make templates` 需要联网，其他已齐备资产的运行/测试不依赖网络。

## 发布前人工确认
查看两套灯光截图与夜晚无后处理对照，确认角色比例、植被、镜头和场景边缘；确认是否需要更精细的 ImageGen/人工美术，再批准视觉方向。
确认项目自己的公开许可证、名称与资源来源；引擎/第三方声明随包保留。没有自动 Git 提交、推送、上传、跨平台保证或外部服务配置。

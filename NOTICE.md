# 来源与第三方声明

本项目的场景代码、程序化像素图和模型生成器为本次项目编写；不包含从《八方旅人》游戏中提取的角色、纹理、模型、音乐、关卡或商标。原作仅作为视觉研究参考，项目与其权利方无官方关联。

当前源美术类型为 `procedural-original`。来源与 SHA-256 见 `art_source/generated/manifest.json`；模型源与生成记录见 `art_source/blender/manifest.json`。ImageGen/Blender MCP 未接入，不将未执行的生成过程写成素材来源。

项目代码与原创美术的公开发布许可由项目所有者选择。本交付不替所有者自动设置 MIT、CC0 或其他公开许可证；引擎许可不等于本项目自身已采用同一许可。

## Godot 与依赖
独立 Linux 可执行文件包含 Godot 及其随附组件。`licenses/GODOT_LICENSE.txt` 与 `licenses/GODOT_THIRD_PARTY.txt` 由 `tools/export_notices.gd` 从实际匹配引擎的 `Engine.get_license_text/get_license_info/get_copyright_info` 导出，随运行包保留。
更新引擎或模板后应重新导出声明并重新测试。方法参考 [Godot 许可说明](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html)。

Blender 和 Pillow 仅作为现有本地制作工具使用，不作为可执行程序分发到运行包；保留模型和生成代码，未打包这些工具的安装文件。没有单独导出或分发系统字体文件。

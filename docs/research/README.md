# 研究与来源

访问记录：2026-09-28。下列为公开技术来源，不代表原作完整渲染实现已公开。

- [SpriteBase3D](https://docs.godotengine.org/en/stable/classes/class_spritebase3d.html)：shaded、Alpha Cut、深度测试和 Billboard 阴影限制。
- [CameraAttributesPractical](https://docs.godotengine.org/en/stable/classes/class_cameraattributespractical.html)：景深在 Forward+/Mobile 可用，不在 Compatibility 可用。
- [Godot 渲染器](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)：功能/平台差异；不可把 Web 与桌面高保真视为同规格。
- [Environment/post-processing](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)：环境、曝光、雾、泛光与 SSR 限制。
- [3D formats / glTF](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)：GLB 推荐，直接 blend 导入需要 Blender。
- [3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html)：TAA 模糊/拖影代价。
- [Blender MCP 源项目](https://github.com/ahujasid/blender-mcp)：第三方任意 Python 执行入口；本轮未安装。
- [八方旅人二代开发者访谈](https://www.unrealengine.com/developer-interviews/octopath-traveler-ii-builds-a-bigger-bolder-world-in-its-stunning-hd-2d-style)：原作视觉方向参考；非参数或素材来源。

## 区分事实与本项目选择
原作参考仅用于像素角色/三维环境/灯光层次。本文工程的相机坐标、Shader、模型和纹理全部为独立实现；不是逆向原作源码。
具体 API 以实际安装引擎的运行结果为准；公开 stable 文档与远端版本可能不同。

- [RenderingServer GPU 计时](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)：独立记录视口 GPU 时间和完成绘制帧间隔。
- [Godot 许可声明](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html)：从匹配引擎导出随包声明。

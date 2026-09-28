# 状态与数据契约

## PixelActor
状态 idle / walking；四朝向 front / back / left / right；同一张图集每朝向四帧（含静止姿态）。
输入无效或对话开启时速度归零。移动向量归一化，斜向不得更快。
落地/碰撞由物理层处理，不根据渲染贴图推断。

## LightingPreset
id ∈ {day, dusk, night}；切换原子应用所有受控属性。
水色、主光、环境色、窗光与局部点光同步；背景素材不重复加载。

## InteractionPoint
id 唯一；world_position 为 Vector3；radius > 0；title/text 不执行代码。
E 开启/关闭最近交互点文本；对话不传送玩家、不访问网络。

## AssetRecipe
source_type = procedural-original / imagegen / authored / third-party。
必须记录生成器路径、seed 或输入 SHA-256、尺寸、透明度约定、license/provenance。
AI 候选不能默认视为连续动画；导入须验证帧尺寸与脚底锚点。

## ValidationRun
环境版本、renderer、viewport、warmup、sample_count、frame_time_percentiles、capture_files、assertions。
标注 headless 或 real-GPU。截图不能证明持续帧率；帧率日志不能证明画面正确。

## P6/P7 更新
P6/P7：LightingPreset 扩展为 day / dusk / night。DOF 用户选择不被时段或全局旁路重置，详见 [扩展契约](background-and-focus.md)。

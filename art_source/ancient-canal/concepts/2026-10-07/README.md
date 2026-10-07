# 江南河街概念选稿

三稿使用相同角色参考、建筑清单、像素细节密度及黄昏光照，分别由内置 ImageGen 并发生成。每稿又进行一次针对性构图修订，初稿阶段共六次调用，选定后另用一次调用绘制实际布局的适配稿。所有首稿、修订原图、提示词和调用来源均保留；随机种子未由工具提供，记录为 null。近景仅从修订原图裁切，没有缩放或重绘。

用户已明确选择 A，并授权适配实际 HD2D 镜头后连续完成制作与验收。适配稿保持当前场景的两岸、桥头酒肆、摊位和码头位置；角色仍使用原有序列帧。行走、受光与交付证据由独立验收报告记录。

默认角色直接复用原有四方向、108 张 256×256 颜色序列帧及其时间线。概念人物仅提供尺度参考，不能替代运行角色。[颜色帧复用基点](../../character-reuse.json)记录了每帧和图集的摘要。

| 稿件 | 构图重点 | 预定主路线 | 选定后需落实 |
| --- | --- | --- | --- |
| A 桥头酒肆 | 横向石桥连接左岸广场与右岸完整酒肆 | 左岸布摊 → 拱桥 → 饮食摊与酒肆 → 右岸码头 | 酒肆平台至码头的下行台阶、桥头通路 |
| B 沿河长街 | 酒肆与街道沿运河向远处延伸 | 近岸酒肆与摊位 → 中景拱桥 → 对岸道路；近岸码头支路 | 被树木和栏杆遮住的桥两端入口与净宽 |
| C 两岸市集 | 开阔市集、偏左拱桥、对岸酒肆正面 | 近岸市集 → 左桥头 → 拱桥 → 对岸酒肆；近岸停船支路 | 将摊位分配到两岸、将陡石阶落实为连续可走桥面 |

## A 实际布局适配

![适配概念](a-runtime-adaptation/concept.png)

[实际布局参考截图](a-runtime-adaptation/actual-layout-reference.png) · [适配提示词](a-runtime-adaptation/prompt.txt) · [来源](a-runtime-adaptation/receipt.json)

适配稿改用俯视街景透视，连续坡面连接两岸，码头有独立下降通路；两层酒肆正面保持可见，近景主角沿用实际投影尺寸。概念中的植物装饰与水面亮纹提供材质参考，运行时受实际几何与可调照明驱动。

## A 桥头酒肆

![A 完整概念](a-bridge-tavern/concept.png)

![A 人物与石路近景](a-bridge-tavern/closeup.png)

[酒肆建筑近景](a-bridge-tavern/tavern-closeup.png) · [详细布局](a-bridge-tavern/layout.md) · [提示词](a-bridge-tavern/prompt.txt) · [修订提示词](a-bridge-tavern/revision-prompt.txt) · [来源记录](a-bridge-tavern/receipt.json) · [首稿](a-bridge-tavern/draft-01.png)

## B 沿河长街

![B 完整概念](b-canal-street/concept.png)

![B 人物与石路近景](b-canal-street/closeup.png)

[酒肆建筑近景](b-canal-street/architecture-closeup.png) · [详细布局](b-canal-street/layout.md) · [修订提示词](b-canal-street/prompt.txt) · [首稿提示词](b-canal-street/prompt-initial.txt) · [来源记录](b-canal-street/receipt.json) · [首稿](b-canal-street/concept-initial.png)

## C 两岸市集

![C 完整概念](c-two-bank-market/concept.png)

![C 人物、桥头与市集近景](c-two-bank-market/closeup.png)

[详细布局](c-two-bank-market/layout.md) · [提示词](c-two-bank-market/prompt.txt) · [修订提示词](c-two-bank-market/revision-prompt.txt) · [来源记录](c-two-bank-market/receipt.json) · [首稿](c-two-bank-market/concept-v1.png)

三稿主角在画面中约占 24%、25%、27% 画高。正式镜头仍以复用角色的实际有效轮廓和脚底锚点确定，不能直接用概念人物像素估计运行贴图比例。未选中的稿件保留为制作历史。

[统一清单](manifest.json)记录最终原图尺寸、摘要、裁切和布局说明；[全部文件摘要](checksums.json)用于核对第一阶段来源。

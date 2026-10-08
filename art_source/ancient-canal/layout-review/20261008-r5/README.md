# Ancient R5 完整施工图

根据用户“输出完整俯视图和侧视图，然后根据两个图重新建模，摆放建筑”的指示应用。继承 R4 的建筑和灯位，不改动 R1–R4 历史审阅稿。

[完整俯视图](full-top-view.png)包含全部前景、近镇与远镇摆放；[完整侧视图](side-view.png)从东侧 +X 朝西侧 −X 看，横轴 Z、纵轴 Y。侧视图中不同 X 的物体会重叠，实际 X 坐标由俯视图确定。[正视图](front-view.png)与[灯位图](lighting-plan.png)补充镜头构图和光源编号。侧视图另存 [SVG](side-view.svg) 和 [PDF](side-view.pdf)。

桥位于 X=1.2，河道中心 Z=2.5；码头在前岸 X=−12，木板顶面 Y=−0.32，坡道沿 Z=5.3～6.6 接岸。酒肆前原 L5 柳树移除，两岸保留五棵柳树；酒肆后方和建筑间隙由十座背景民居、十棵平面树填充。保留十四个灯控制 ID；C1 在桥心，P6 为码头暖灯，默认半径 4.5 米、关闭阴影。

图中建筑轮廓依据现有模型的真实包围盒，摆放数据使用模型原点。树木是竖直平面卡片，图示树冠不能当作实体碰撞范围。灯位星点表示发光点，灯具脚点另列于 JSON / CSV，避免把灯柱落到水面或坡道上。

施工依据为 [layout.review.json](layout.review.json)、[placement.csv](placement.csv)和[lights.csv](lights.csv)。生成器 `tools/ancient_canal/build_layout.py --apply` 将该 JSON 编译为运行布局；无 `--apply` 时核对运行布局是否完全一致。道路、地面缺口、码头坡道、建筑与光源采用同一套坐标。

[可编辑三维总装](../../layout-assembly/20261008-r5/ancient-r5.blend)按此图生成，保留独立建筑实例及打包纹理。运行场景仍使用独立模型和三组路面网格，以便编辑及控制性能。实际 GPU 图像、视频与回归结果在 `docs/ancient-canal/layout-r5-20261008/` 归档。

重绘：`MPLCONFIGDIR=/tmp/ancient-layout-review-mpl python3 art_source/ancient-canal/layout-review/20261008-r5/draw.py`。图纸为确定性矢量绘制，未引入外部素材。

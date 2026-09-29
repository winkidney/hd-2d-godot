"""Build the review report and verify the independent frontal deliverables."""
from pathlib import Path
import json,sys,shutil,zipfile,subprocess
from PIL import Image,ImageDraw,ImageFont
from run import ROOT,OUT,sha,save,source_files,fingerprint
DOC=ROOT/'docs/validation/p9-frontal'

def load(p):return json.loads(p.read_text())
def sheet(items,columns,path,tile=(640,360)):
    w,h=tile;band=36
    canvas=Image.new('RGB',(w*columns,(h+band)*((len(items)+columns-1)//columns)),(18,24,29))
    draw=ImageDraw.Draw(canvas);font=ImageFont.load_default(size=20)
    for i,(label,source) in enumerate(items):
        im=Image.open(source).convert('RGB');im.thumbnail(tile,Image.Resampling.LANCZOS)
        x=i%columns*w;y=i//columns*(h+band)
        canvas.paste(im,(x+(w-im.width)//2,y+band+(h-im.height)//2));draw.text((x+12,y+6),label,font=font,fill='white')
    canvas.save(path)

def report():
    DOC.mkdir(parents=True,exist_ok=True)
    gpu=load(OUT/'gpu/report.json');headless=load(OUT/'headless/report.json')
    assert gpu['passed'] and headless['passed']
    sheet([(v+' | dusk | full effects',OUT/'gpu'/f'{v}-dusk-center-dof-on.png') for v in 'FWO'],3,DOC/'three-way.png')
    sheet([(v+' | '+side+' | DOF off',OUT/'gpu'/f'{v}-dusk-{side}-dof-off.png') for v in 'FWO' for side in ('left','center','right')],3,DOC/'left-center-right.png')
    sheet([(v+' | '+period,OUT/'gpu'/f'{v}-{period}-center-dof-on.png') for v in 'FWO' for period in ('day','dusk','night')],3,DOC/'three-periods.png')
    sheet([('User ImageGen concept | research only',ROOT/'art_source/reference-scene/originals/canal-extension-concept-upload-20260929.png'),('New frontal reconstruction | F',OUT/'gpu/F-dusk-center-dof-on.png')],2,DOC/'concept-comparison.png',tile=(960,540))
    angles=[];performance=[];maximum_frame=0;maximum_gpu=0
    for v in 'FWO':
        observations=headless['variants'][v]['route']['side_observations']
        values=[observations['view_'+s]['geometric_angle_degrees'] for s in ('left','center','right')]
        angles.append('| '+v+' | '+' | '.join(f'{x:+.2f}°' for x in values)+' |')
        for period,p in gpu['variants'][v]['performance'].items():
            assert p['duration_s']>=30 and p['target_60fps_p95_met']
            performance.append(f'| {v} | {period} | {p["duration_s"]:.2f} | {p["p95_ms"]:.3f} | {p["gpu"]["p95_ms"]:.3f} | {p["rendering_video_memory_bytes"]/1024**2:.1f} |')
            maximum_frame=max(maximum_frame,p['p95_ms']);maximum_gpu=max(maximum_gpu,p['gpu']['p95_ms'])
    max_error=max(gpu['variants'][v]['fixtures']['markers']['max_error_px'] for v in 'FWO')
    text=f'''# P9R2 正面运河审阅

旧四方案已提交为 `171e632`，没有推送。本轮另建正面运河场景，保留F/W/O三组镜头；新工作未自动提交。旧A/B/C/D和旧场景不修改。

## 打开与对比

解压 `frontal-canal-linux.zip` 后运行 `./frontal-canal.x86_64`。F9切换F/W/O、恢复本组默认值或运行共同路线。WASD/方向键行走，E交互，T切时段，F6景深，F8视差，Esc关闭面板或取消路线。

先看 `three-way.mp4`，三段同路线同步横向对照。`F.mp4`、`W.mp4`、`O.mp4`保留完整1080p画面。比较入口默认为F，不替用户选定最终方案。

![三组中央构图](three-way.png)

## 实际改变

新场景取消旧镜头约27°的斜向观察，中央朝向正对主建筑。重排双岸、桥闸、高台、台阶、市场、码头和远景，不是给旧场景改一个相机标签。三组都是透视投影，没有正交镜头或建筑多视图贴片。

| 组 | 镜头 | 差别与审阅重点 |
|---|---|---|
| F 稳定正面 | 35°FOV，14°俯角，30m半径，朝向固定 | 平移就能真实换侧。构图较稳，作为新基线推荐 |
| W 较强纵深 | 45°FOV，12°俯角，23m半径，朝向固定 | 近远缩放和侧墙更明显，人物在中央比F稍大，边缘透视变化也更强 |
| O 轻微绕转 | F基础上增加±4°位置驱动偏航 | 侧面变化更强，中央与F相同，区别需要看行走段。运动舒适度仍需真人审阅 |

三组共享完整三维模型、材质和49个碰撞体。横向跟随默认0.7；偏航只属于O。靠左时相机跨到主楼左外墙之外，靠右时跨到右外墙之外，因此两面是真实几何露出，不是图片替换。道路、建筑和碰撞不跟随镜头移动。

| 组 | 左端观察角 | 中央观察角 | 右端观察角 |
|---|---:|---:|---:|
{chr(10).join(angles)}

这些角度取真实物理路线停步后的主楼到相机射线。左右墙体投影均有至少1500px²可见面积且宽度至少16px，主楼完整轮廓另用GLB顶点检查；截图保持1920×1080原视域，没有扩宽视口补救。

![左右换侧](left-center-right.png)

## 验收结果

| 项目 | 结果 |
|---|---|
| 相机数学 | 2115项通过，全部透视，中央正面、低俯角、两侧模型完整在画面内、参数隔离与预览恢复 |
| 源素材 | 571项检查通过，两张ImageGen原图、处理配方、23张运行PNG和16套Blender源/GLB延续已提交生产链 |
| 实际路线 | 三组各25站，headless每组2253移动物理帧；30fps录制每组2256移动物理帧，三组录像轨迹误差为0。桥、楼梯、高台、码头及交互通过，零跌落恢复 |
| 状态/物理 | {len(headless['checks'])}项通过，切换保留玩家/时段/景深，碰撞不变，输入方向和停步收敛正常 |
| 源码GPU | {len(gpu['checks'])}项通过，54张场景截图；原生近/远景深棋盘和焦内保护实测通过 |
| P7天空 | 三组各三时段配色同步，近远两层云均处于真实视锥和远裁切范围内 |
| P8视差 | 250个五层标记测量，最大绝对/位移质心误差{max_error:.3f}px，阈值0.8px。O覆盖−4/0/+4°，倍率0/0.5/1/1.5/2 |
| 旧场景 | make test通过，含410项P8及跨进程设置恢复；旧脚本和旧场景文件没有改动 |
| 独立包/干净副本 | 独立二进制启动验证；新world从布局重新烘焙，使用全新Godot导入缓存，原素材来源检查通过 |

P8只补偿横向平移引起的背景位移，O的绕转保持自然。每层代表点精确不代表厚背景所有顶点都能精确，极端倍率仍可能暴露分层关系。所有观察组均保留，不以自动化结果代替视觉批准。

### 性能

{gpu['gpu']}，Godot {gpu['engine']}，1080p Forward+，VSync关闭。每组每时段实际墙钟采样至少30秒。最大帧间隔P95 {maximum_frame:.3f}ms，最大GPU P95 {maximum_gpu:.3f}ms。只代表本机，显存为引擎报告值。

| 组 | 时段 | 秒 | 帧间隔P95 ms | GPU P95 ms | 显存MiB |
|---|---|---:|---:|---:|---:|
{chr(10).join(performance)}

![三个时段](three-periods.png)

## 仍需你审阅的地方

推荐先看F，再看O的换侧行走段；偏好明显纵深可以选W。三者都实现真实左右换侧，但美术还不能称为原作级还原。建筑模块重复、前方广场较规整、云层较卡通，灯具局部发白，市场密度和曲线台阶不及概念图。F/O中央画面本来就相同，不能用静态中央图判断绕转收益。

录像抽检发现O约21.5秒处前景路灯遮住主角大部分躯干，但头仍可见；F同处灯贴近主角，W更分开。码头栏杆会遮小腿。当前没有角色遮挡淡出系统，不宣称全程无遮挡；主楼两侧观察点的角色物理视线和实际截图已检查。像素密度随透视距离变化，这是本轮真实透视的代价。夜景更强调灯光，人物在无灯处较暗。详细抽检见 `video-review.md`。

![概念与新场景](concept-comparison.png)

## 来源和复现

没有新依赖、没有启用Blender MCP、没有使用概念整图当场景，也没有从原作截图提取纹理或角色。新场景复用已提交的原创模块及ImageGen派生纹理，所有.blend、.glb和生成脚本随完整工程保留。原图文件/像素散列与历史差异仍在原来源manifest，新场景另有 `art_source/frontal-canal/manifest.json`。

`frontal-complete-project.zip` 保留旧场景、旧四方案和新三组实现。新独立包默认进入新场景。原作研究截图不进入源码包和运行包，只在单独研究对照图里展示。

干净副本的新World与原World除了Godot自动生成的node unique_id以外，序列化文本逐字节一致；两个原始SHA不同，规范化检查另有SHA记录，没有宣称原文件字节一致。

命令入口：`make frontal-test`、`make frontal-visual`、`make frontal-record`、`make frontal-export`、`make frontal-rebuild`、`make frontal-package`。工程默认启动旧场景不变，使用 `make frontal-run` 进入新场景。详细过程见 `workflow.md` 与 `execution-log.md`。交付完整性见 `SHA256SUMS`。
'''
    (DOC/'README.md').write_text(text)

def package():
    report()
    gpu=load(OUT/'gpu/report.json')
    assert gpu['runtime_fingerprint']==fingerprint(ROOT)['sha256'],'Stale GPU evidence'
    for name in ['standalone-headless','standalone-gpu','rebuild-headless','rebuild-quick']:
        assert load(OUT/name/'report.json')['passed']
    assert load(OUT/'export-report.json')['passed'] and load(OUT/'rebuild-report.json')['passed']
    assert load(OUT/'rebuild-report.json')['scene_identical_except_generated_node_unique_ids']
    assert load(OUT/'ui/report.json')['passed']
    assert all(load(OUT/'settings'/(mode+'-report.json'))['passed'] for mode in ['save','load','restore-defaults'])
    assert load(OUT/'media/video-report.json')['passed']
    folder=OUT/'delivery';folder.mkdir(exist_ok=True)
    binary=OUT/'linux/frontal-canal.x86_64'
    assert sha(binary)==load(OUT/'export-report.json')['binary_sha256']
    with zipfile.ZipFile(folder/'frontal-canal-linux.zip','w',zipfile.ZIP_DEFLATED) as z:
        z.write(binary,binary.name);z.write(ROOT/'NOTICE.md','NOTICE.md')
        z.writestr('README.txt','Run ./frontal-canal.x86_64\nF9: F/W/O cameras and common physical route. WASD: walk. E: interact. T: time. F6: DOF. F8: parallax.\nAll three use real perspective and real building geometry. See comparison.md for limitations.\n')
        for p in (ROOT/'licenses').rglob('*'):
            if p.is_file():z.write(p,p.relative_to(ROOT))
    with zipfile.ZipFile(folder/'frontal-complete-project.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in source_files(ROOT):
            if 'research' not in p.parts:z.write(p,p.relative_to(ROOT))
    with zipfile.ZipFile(folder/'frontal-evidence.zip','w',zipfile.ZIP_DEFLATED) as z:
        for name in ['gpu','headless','standalone-headless','standalone-gpu','rebuild-headless','rebuild-quick','ui','settings','media']:
            for p in (OUT/name).rglob('*'):
                if p.suffix=='.json' or (name in ['gpu','ui'] and p.suffix=='.png'):z.write(p,p.relative_to(OUT))
        for p in OUT.glob('*.json'):z.write(p,p.name)
    for p in (OUT/'media').glob('*.mp4'):shutil.copy2(p,folder/p.name)
    for p in DOC.glob('*.png'):shutil.copy2(p,folder/p.name)
    for p in (OUT/'ui').glob('*.png'):shutil.copy2(p,folder/p.name)
    for name in ['source-audit.md','video-review.md']:shutil.copy2(DOC/name,folder/name)
    for source,target in [(DOC/'README.md','comparison.md'),(DOC/'execution-log.md','execution-log.md'),(ROOT/'docs/workflows/p9-frontal.md','workflow.md'),(ROOT/'Plan/features/p9-frontal-rebuild.md','plan.md'),(ROOT/'art_source/frontal-canal/manifest.json','source-manifest.json')]:shutil.copy2(source,folder/target)
    research=ROOT/'art_source/reference-scene/research/otc-path-traveler.png'
    if research.exists():sheet([('Original game | research only',research),('Original reconstruction | actual F GPU',OUT/'gpu/F-dusk-center-dof-on.png')],2,folder/'reference-study.png',tile=(960,540))
    save(folder/'delivery-report.json',{'passed':True,'checkpoint':'171e632','new_changes_committed':False,'pushed':False,'runtime_fingerprint':gpu['runtime_fingerprint'],'binary_sha256':sha(binary),'visual_review_pending':True})
    for p in folder.glob('*.zip'):
        with zipfile.ZipFile(p) as z:assert z.testzip() is None
    (folder/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in sorted(folder.iterdir()) if p.name!='SHA256SUMS'))
    print('FRONTAL_DELIVERY',folder)

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='report':report()
    else:package()

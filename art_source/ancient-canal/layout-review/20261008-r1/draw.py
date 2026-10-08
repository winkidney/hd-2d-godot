"""Measured review drawings from one coordinate file. Does not mutate the scene."""
from pathlib import Path
import csv, hashlib, json, math, sys
from datetime import datetime, timezone
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Polygon, Ellipse, Circle
from matplotlib.font_manager import FontProperties, fontManager
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
DATA = json.loads((HERE / "layout.review.json").read_text())
fontManager.addfont("/usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf")
FONT = FontProperties(family=["DejaVu Sans", "Droid Sans Fallback"])
plt.rcParams.update({"font.family": FONT.get_name(), "svg.fonttype":"path", "svg.hashsalt":"ancient-layout-review-r1", "axes.unicode_minus":False})
PAPER="#f7f3e8"; INK="#243d43"; SOFT="#72858a"; WATER="#aed4d9"; ROAD="#e5ddc7"
ROOF="#9ca9a9"; TAVERN="#b47a51"; STALL="#d6a365"; LINE="#138b91"; PLANT="#789480"


def label(ax,x,y,text,size=11,color=INK,ha="center",va="center",**kw):
    return ax.text(x,y,text,fontproperties=FONT,fontsize=size,color=color,ha=ha,va=va,**kw)


def rect(ax,x0,z0,x1,z1,face,edge=INK,lw=.8,**kw):
    ax.add_patch(Rectangle((x0,z0),x1-x0,z1-z0,facecolor=face,edgecolor=edge,linewidth=lw,**kw))


def dim(ax,a,b,text,vertical=False):
    ax.annotate("",xy=b,xytext=a,arrowprops=dict(arrowstyle="|-|",color=INK,lw=.9))
    label(ax,(a[0]+b[0])/2+(.55 if vertical else 0),(a[1]+b[1])/2+ (0 if vertical else -.4),text,10,rotation=90 if vertical else 0,bbox=dict(facecolor=PAPER,edgecolor="none",pad=1))


def roof_bounds(obj):
    x,_,z=obj["position"];b=obj["model_bounds"]
    return (x+b["min"][0],z+b["min"][2],x+b["max"][0],z+b["max"][2])


def top(ax):
    ax.set_facecolor(PAPER);ax.set_xlim(-29,29);ax.set_ylim(15.7,-18.6);ax.set_aspect("equal")
    ax.set_xticks(np.arange(-25,26,5));ax.set_yticks([-16,-10,-5,0,5,10,14]);ax.tick_params(labelsize=9,length=0,pad=6,colors=SOFT)
    ax.set_xticks(np.arange(-26,27,1),minor=True);ax.set_yticks(np.arange(-16,15,1),minor=True)
    ax.tick_params(which="minor",length=0);ax.grid(which="minor",color="#dcded5",lw=.35,zorder=0)
    for s in ax.spines.values():s.set_visible(False)
    rect(ax,-26,-16,26,14,"none",SOFT,1.4,linestyle=(0,(5,4)),zorder=1)
    rect(ax,-26,-.1,26,5.1,WATER,"#568d99",1,zorder=2)
    for z in [.8,2,3.2,4.4]:
        ax.plot([-25.5,25.5],[z,z],color="#cce6e6",lw=.6,zorder=3)
    for key in ["rear","front","rear_service","bridge_alley"]:
        s=DATA["streets"][key];rect(ax,s["x"][0],s["z"][0],s["x"][1],s["z"][1],ROAD,"#c8bea9",.6,zorder=2)
    a=DATA["tavern_forecourt"];rect(ax,*[a["x"][0],a["z"][0],a["x"][1],a["z"][1]],"#d8e5dc",PLANT,.7,zorder=2)
    for obj in DATA["objects"]:
        x,_,z=obj["position"];x0,z0,x1,z1=roof_bounds(obj);size=obj["collision_size"]
        face=TAVERN if obj["asset"]=="tavern" else STALL if obj["id"].startswith("S") else ROOF
        rect(ax,x0,z0,x1,z1,face,INK,1.1,zorder=5)
        ax.plot([x0+.2,x1-.2],[(z0+z1)/2]*2,color=INK,lw=.8,zorder=6)
        rect(ax,x-size[0]/2,z-size[2]/2,x+size[0]/2,z+size[2]/2,"none",INK,.65,linestyle=(0,(3,3)),zorder=7)
        center=(z0+z1)/2
        content=obj["id"]+"  "+obj["label"] if not obj["id"].startswith("S") else obj["id"]+"\n"+obj["label"]
        label(ax,x,center if obj["id"].startswith("S") else center-.6,content,12 if obj["id"].startswith("S") else 11,color="#fffdf3",zorder=8)
        if not obj["id"].startswith("S"):
            label(ax,x,center+.65,f"({x:g}, {z:g})",9,color="#fffdf3",zorder=8)
            rect(ax,x-.8,z1+.05,x+.8,-3.8,"#f1eee2","none",zorder=3)
            ax.annotate("",xy=(x,-4),xytext=(x,z1+.1),arrowprops=dict(arrowstyle="->",color=SOFT,lw=1),zorder=9)
    for obj in DATA["objects"]:
        if obj["id"].startswith("S"):
            x=obj["position"][0];rect(ax,x-1.6,-4.6,x+1.6,-3.8,"#efe5bc","#ae9b5c",.6,hatch="...",zorder=4)
    # Parallel river bridge, retaining the measured overall rail envelope.
    rect(ax,-.445,-1.84,2.845,6.84,"#b6b7ab",INK,1,zorder=10)
    rect(ax,-.2,-1.7,2.6,6.7,"#e3e1cf",INK,.65,zorder=11)
    for z in np.linspace(-1.6,6.6,17):ax.plot([-.15,2.55],[z,z],color="#adada1",lw=.4,zorder=12)
    label(ax,1.2,2.5,"石\n拱\n桥",12,zorder=13)
    rect(ax,-13,-.3,-11,2.7,"#ac845d",INK,1,zorder=8)
    for z in np.linspace(-.25,2.65,15):ax.plot([-12.95,-11.05],[z,z],color="#7c644d",lw=.5,zorder=9)
    rect(ax,-12.825,-1.6,-11.175,-.3,"#c5a27a",INK,.7,zorder=9)
    ax.annotate("",xy=(-12,1.9),xytext=(-12,-1.5),arrowprops=dict(arrowstyle="->",color="#fff7df",lw=1.2),zorder=10)
    label(ax,-15.1,.5,"木码头\nY=−0.32",10,zorder=10)
    ax.plot([-14,-13],[.5,.5],color=INK,lw=.7,zorder=10)
    boat=DATA["boat"];x,_,z=boat["center"];b=boat["model_bounds"]
    bx0,bx1=x+b["min"][2],x+b["max"][2];bz0,bz1=z-b["max"][0],z-b["min"][0]
    ax.add_patch(Polygon([(bx0,z),(bx0+.6,bz0),(bx1-.6,bz0),(bx1,z),(bx1-.6,bz1),(bx0+.6,bz1)],facecolor="#806750",edgecolor=INK,lw=1,zorder=7))
    label(ax,x,z,"泊船",10,color="#fff4db",zorder=8);ax.plot([-11,bx0],[1.4,z],color=INK,lw=.8,zorder=11)
    for x,y,z in DATA["willows"]:
        ax.add_patch(Ellipse((x,z),4.8,2.4,facecolor="#cedbd0",edgecolor=PLANT,lw=.8,linestyle=(0,(3,3)),zorder=4))
        ax.add_patch(Circle((x,z),.19,facecolor=INK,zorder=5));label(ax,x,z+1.6,"平面柳树",9,color=PLANT,zorder=8)
    ax.plot([-24.3,24.3],[-2.4,-2.4],color=LINE,lw=2,linestyle=(0,(5,3)),zorder=14)
    ax.plot([-24.3,24.3],[8.5,8.5],color=LINE,lw=2,linestyle=(0,(5,3)),zorder=14)
    ax.plot([1.2,1.2],[-2.4,-1.9],color=LINE,lw=2,zorder=14);ax.plot([1.2,1.2],[6.9,8.5],color=LINE,lw=2,zorder=14)
    ax.plot([-12,-12],[-2.4,-1.9],color=LINE,lw=1.5,zorder=14)
    for index,npc in enumerate(DATA["npcs"],1):
        x,_,z=npc["position"];ax.add_patch(Circle((x,z),.31,facecolor="#bc5a38",edgecolor=PAPER,lw=1,zorder=16));label(ax,x,z,str(index),8,color="white",zorder=17)
    label(ax,13.5,-2.4,"后岸街 · 连续通行",10,bbox=dict(facecolor=ROAD,edgecolor="none",pad=2),zorder=15)
    label(ax,12,8.5,"前岸步道 · 镜头跟随横移",11,bbox=dict(facecolor=ROAD,edgecolor="none",pad=2),zorder=15)
    label(ax,13,3,"横向河道  /  Z=2.5",12,color="#366e7c",zorder=6)
    label(ax,1.2,-10,"桥轴留空\n6.8 m",11,color=SOFT,zorder=9)
    label(ax,-9.5,-4.3,"酒肆院坪",9,color="#517e69",zorder=10)
    label(ax,-10,-15,"后巷 1.0 m",8,color=SOFT,zorder=10)
    label(ax,0,-18.3,"俯视图 · 所有建筑中心与屋檐按同一坐标文件绘制",14,ha="center")
    dim(ax,(-26,-17.1),(26,-17.1),"可行走地图宽 52.0 m")
    dim(ax,(-27.5,-16),(-27.5,14),"30.0 m",True)
    dim(ax,(27.1,-.1),(27.1,5.1),"河宽 5.2 m",True)
    dim(ax,(-25.8,-3.8),(-25.8,-1),"2.8 m",True)
    dim(ax,(-25.8,6.4),(-25.8,10.6),"4.2 m",True)
    dim(ax,(3.7,-1.7),(3.7,6.7),"桥跨度 8.4 m",True)
    dim(ax,(-.2,7.8),(2.6,7.8),"2.8 m")
    ax.annotate("",xy=(23.5,-13.8),xytext=(23.5,-10.2),arrowprops=dict(arrowstyle="->",color=INK,lw=1.5));label(ax,23.5,-14.4,"−Z 后岸",10)
    ax.annotate("",xy=(21,6),xytext=(21,10.8),arrowprops=dict(arrowstyle="->",color=INK,lw=1.3));label(ax,20.5,11.4,"正视方向",9,zorder=20)
    ax.set_xlabel("X / 米   左负右正",fontproperties=FONT,fontsize=10,color=SOFT,labelpad=5)


def elevation(ax):
    ax.set_xlim(-29,29);ax.set_ylim(-1.6,8.5);ax.set_aspect("equal");ax.set_facecolor(PAPER)
    ax.set_xticks(np.arange(-25,26,5));ax.set_yticks([-.62,0,2,4,6]);ax.tick_params(labelsize=9,length=0,colors=SOFT)
    for s in ax.spines.values():s.set_visible(False)
    ax.axhline(0,color=INK,lw=1);ax.axhline(-.62,color="#6597a3",lw=1)
    rect(ax,-26,-.9,26,-.62,WATER,"none")
    for obj in sorted(DATA["objects"],key=lambda o:o["position"][2]):
        x=obj["position"][0];b=obj["model_bounds"];x0=x+b["min"][0];x1=x+b["max"][0];height=b["max"][1]
        is_stall=obj["id"].startswith("S");is_tav=obj["id"]=="T1"
        eave=height-(.35 if is_stall else .75)
        rect(ax,x0+.3,0,x1-.3,eave,"#cfb595" if is_tav else "#e0d8c4",INK,.7,zorder=3)
        ax.add_patch(Polygon([(x0,eave),(x0+.65,eave+.55*(height-eave)),(x, height),(x1-.65,eave+.55*(height-eave)),(x1,eave)],facecolor=STALL if is_stall else TAVERN if is_tav else ROOF,edgecolor=INK,lw=.9,zorder=4))
        if is_stall:
            for xx in [x0+.22,x1-.22]:rect(ax,xx-.045,0,xx+.045,eave,"#8c6747",INK,.3,zorder=5)
            rect(ax,x0+.25,.72,x1-.25,1.03,STALL,INK,.6,zorder=5)
        else:
            rect(ax,x-.48,0,x+.48,1.65,"#725743",INK,.7,zorder=5)
            for xx in [x-1.4,x+1.4]:rect(ax,xx-.36,.95,xx+.36,1.65,"#dcbb70",INK,.6,zorder=5)
            if is_tav:
                ax.plot([x0+.2,x1-.2],[2.72,2.72],color=INK,lw=1,zorder=5)
                for xx in [x-1.6,x,x+1.6]:rect(ax,xx-.4,3.25,xx+.4,4.15,"#dcbb70",INK,.6,zorder=5)
        label(ax,x,height+.55,obj["id"]+"  "+obj["label"],10,zorder=6)
    rect(ax,-13,-.48,-11,-.32,"#aa815c",INK,.7,zorder=7)
    boat=DATA["boat"];x=boat["center"][0];b=boat["model_bounds"]
    ax.add_patch(Polygon([(x+b["min"][2],-.25),(x+b["min"][2]+.5,-.6),(x+b["max"][2]-.5,-.6),(x+b["max"][2],-.25)],facecolor="#806750",edgecolor=INK,lw=.8,zorder=7))
    rect(ax,x-.8,-.24,x+.8,.48,"#aa815c",INK,.6,zorder=7)
    rect(ax,-.2,-.62,2.6,.6,"#b6b7ab",INK,.8,zorder=7)
    for xx in [-.43,2.83]:rect(ax,xx-.11,.3,xx+.11,1.63,"#a0a99f",INK,.6,zorder=8)
    ax.plot([-.35,2.75],[1.63,1.63],color=SOFT,lw=.7,zorder=8)
    for index,npc in enumerate(DATA["npcs"],1):
        x,y,z=npc["position"];ax.add_patch(Circle((x,y+1.45),.13,facecolor="#bc5a38",edgecolor=INK,lw=.4,zorder=9));rect(ax,x-.15,y,x+.15,y+1.3,"#bc5a38",INK,.4,zorder=9)
    for x,y,z in DATA["willows"]:
        rect(ax,x-.10,0,x+.10,3.8,PLANT,"none",zorder=10)
        ax.add_patch(Ellipse((x,4.2),4.8,3.7,facecolor="#d1ddce",edgecolor=PLANT,lw=.6,alpha=.75,zorder=10))
        for dx in [-1.8,-1,-.2,.6,1.4]:ax.plot([x+dx,x+dx+.1],[5.0,1.6+abs(dx)*.3],color=PLANT,lw=.6,zorder=11)
    label(ax,12,7.8,"正视图 · 从前岸 +Z 看向后岸 −Z",14)
    label(ax,12,6.8,"正交立面示意；屋高取模型包围盒，檐口与门窗为示意",9,color=SOFT)
    label(ax,18,-1.1,"水面 Y=−0.62  /  岸面 Y=0",9,color=SOFT)
    label(ax,1.2,2.1,"桥面最高 +0.60",9)
    ax.set_ylabel("Y / 米",fontproperties=FONT,fontsize=10,color=SOFT)


def side_section(ax):
    ax.set_xlim(-5.2,5.2);ax.set_ylim(-1.1,2.0);ax.set_aspect("equal");ax.axis("off")
    xs=np.linspace(-4.2,4.2,90);ys=.6*(1-(xs/4.2)**2)
    ax.fill_between(xs,ys-.24,ys,color="#b6b7ab");ax.plot(xs,ys,color=INK,lw=1)
    ax.plot(xs,ys+1.03,color=SOFT,lw=.6);ax.plot([-5.2,5.2],[-.62,-.62],color="#6597a3",lw=1)
    ax.plot([-5.2,-4.2],[0,0],color=INK,lw=1);ax.plot([4.2,5.2],[0,0],color=INK,lw=1)
    dim(ax,(-4.2,-.95),(4.2,-.95),"8.4 m")
    label(ax,0,1.86,"桥纵剖面补充 · 桥面起伏 0.6 m",10)


def review_checks():
    failures=[];bounds={o["id"]:roof_bounds(o) for o in DATA["objects"]}
    for id,b in bounds.items():
        if not (-26<=b[0]<b[2]<=26 and -16<=b[1]<b[3]<=14):failures.append(id+": outside boundary")
    for index,(aid,a) in enumerate(bounds.items()):
        for bid,b in list(bounds.items())[index+1:]:
            if max(a[0],b[0])<min(a[2],b[2]) and max(a[1],b[1])<min(a[3],b[3]):failures.append(aid+"/"+bid+": roof overlap")
    for key in ["rear","front","bridge_alley","rear_service"]:
        road=DATA["streets"][key];r=(road["x"][0],road["z"][0],road["x"][1],road["z"][1])
        for id,b in bounds.items():
            if max(r[0],b[0])<min(r[2],b[2]) and max(r[1],b[1])<min(r[3],b[3]):failures.append(id+": street roof encroachment")
    for house in [o for o in DATA["objects"] if not o["id"].startswith("S")]:
        x=house["position"][0];f=bounds[house["id"]][3];r=(x-.8,f,x+.8,-3.8)
        for id,b in bounds.items():
            if id!=house["id"] and max(r[0],b[0])<min(r[2],b[2]) and max(r[1],b[1])<min(r[3],b[3]):failures.append(house["id"]+": doorway blocked")
    sys.path.insert(0,str(ROOT/"tools"));from feature_fingerprint import fingerprint
    before=json.loads((HERE/"runtime-before.json").read_text());unchanged=fingerprint(ROOT)["sha256"]==before["runtime_fingerprint"]
    report={"passed":not failures and unchanged,"failures":failures,"runtime_unchanged":unchanged,"roof_bounds":bounds,"checks":["7 measured roof envelopes inside map","no building/stall roof envelope overlap","streets and bridge alley clear of roofs","four 1.6m entrance corridors clear of other roofs","runtime fingerprint unchanged"],"scope":"Static layout geometry only. Collision and in-game visibility will be validated after user approval and placement."}
    (HERE/"review-checks.json").write_text(json.dumps(report,indent=2)+"\n")
    assert report["passed"],report


def main():
    review_checks()
    fig=plt.figure(figsize=(24,20),facecolor=PAPER)
    fig.text(.045,.965,"Ancient 河街建筑摆放图",fontproperties=FONT,fontsize=28,color=INK)
    fig.text(.045,.938,"R1 审阅稿  /  2026-10-08  /  单位：米  /  按现有模型尺寸设计",fontproperties=FONT,fontsize=12,color=SOFT)
    top(fig.add_axes([.04,.385,.75,.52]));elevation(fig.add_axes([.04,.095,.75,.235]))
    note=fig.add_axes([.815,.34,.17,.57]);note.axis("off")
    entries=[("构图关系",["后巷 → 建筑 → 院坪/摊位","→ 后岸街 → 河 → 前岸步道","中央桥轴留空，房屋入口错开摊位。"]),
             ("通行尺寸",["后岸街 2.8 m，中心 Z=−2.4","码头入口处至少保留 2.2 m","前岸步道 4.2 m，中心 Z=8.5","桥头通向后巷，留空宽 6.8 m","摊前另留 0.8 m 停留带"]),
             ("建筑中心  X / Z",[f"{o['id']} {o['label']}   {o['position'][0]:g} / {o['position'][2]:g}" for o in DATA["objects"]]),
             ("驻点人物",[f"{i}. {n['label']}" for i,n in enumerate(DATA["npcs"],1)]),
             ("读图",["外实线：模型屋檐投影范围","内虚线：现有碰撞占地","蓝绿虚线：主要通行中心线","暖色点：NPC 驻点","树椭圆仅示意冠幅，碰撞仅树干"])]
    y=1
    for title,lines in entries:
        note.text(0,y,title,fontproperties=FONT,fontsize=13,color=INK,va="top");y-=.036
        for line in lines:
            note.text(0,y,line,fontproperties=FONT,fontsize=10,color=SOFT,va="top");y-=.029
        y-=.027
    side_section(fig.add_axes([.815,.10,.17,.18]))
    fig.text(.045,.053,"审阅重点：酒肆与码头是否相邻合适；三摊是否应集中；前岸是否继续保留开阔步道。",fontproperties=FONT,fontsize=12,color=INK)
    fig.text(.045,.030,"本图与坐标文件一一对应。确认后依此摆放；此阶段未改运行场景。平面、正视及剖面为设计图，非 GPU 渲染验收。",fontproperties=FONT,fontsize=10,color=SOFT)
    for suffix in ["png","svg","pdf"]:
        metadata={"Creator":"Ancient layout review","CreationDate":datetime(2026,10,8,tzinfo=timezone.utc)} if suffix=="pdf" else None
        fig.savefig(HERE/("layout-review."+suffix),dpi=150,facecolor=PAPER,metadata=metadata)
    plt.close(fig)
    for name,fn,size in [("top-view",top,(18,11)),("front-view",elevation,(20,5))]:
        f=plt.figure(figsize=size,facecolor=PAPER);fn(f.add_axes([.05,.08,.9,.85]));f.savefig(HERE/(name+".png"),dpi=160,facecolor=PAPER);plt.close(f)
    with (HERE/"placement.csv").open("w") as stream:
        writer=csv.writer(stream);writer.writerow(["id","asset","label","x_m","y_m","z_m","yaw_deg"])
        for o in DATA["objects"]:writer.writerow([o["id"],o["asset"],o["label"],*o["position"],o["yaw_deg"]])
    print("REVIEW_DRAWINGS_READY: top/front/combined PNG, SVG, PDF, coordinates and geometry checks")

if __name__=="__main__":main()

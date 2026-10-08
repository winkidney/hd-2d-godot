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
plt.rcParams.update({"font.family": FONT.get_name(), "svg.fonttype":"path", "svg.hashsalt":"ancient-layout-review-r4", "axes.unicode_minus":False})
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


def top_lights(ax):
    for o in DATA["lights"]:
        x,y,z=o["position"];code=o["diagram_id"];cool=code=="C1";color="#438bb4" if cool else "#b87829"
        if code in ["C1","P6"]:
            ax.add_patch(Circle((x,z),o["range_m"],facecolor="#91c7dc" if cool else "#e4b764",edgecolor=color,alpha=.13,lw=1,linestyle=(0,(5,4)),zorder=13))
        if o["kind"]=="streetlamp":
            fx,fy,fz=o["fixture_position"]
            ax.add_patch(Circle((fx,fz),o["collision_radius"],facecolor=PAPER,edgecolor=INK,lw=.8,zorder=22))
            ax.plot([fx,x],[fz,z],color=INK,lw=.7,zorder=22)
        ax.plot(x,z,marker="D" if o["kind"]=="lantern" else "*",markersize=6 if o["kind"]=="lantern" else 16 if cool else 11,color=color,markeredgecolor=PAPER,markeredgewidth=.8,zorder=23)
        lx,lz=o["diagram_label_position_xz"]
        ax.plot([x,lx],[z,lz],color=color,lw=.55,zorder=21)
        title=code+" "+o["label"] if code in ["C1","W1","P6"] else code
        label(ax,lx,lz,title,10 if code in ["C1","P6"] else 9,color=color,bbox=dict(facecolor=PAPER,edgecolor="none",alpha=.88,pad=.8),zorder=24)


def elevation_lights(ax):
    for o in DATA["lights"]:
        x,y,z=o["position"];code=o["diagram_id"];color="#438bb4" if code=="C1" else "#b87829"
        if o["kind"]=="streetlamp":
            fx,fy,fz=o["fixture_position"]
            rect(ax,fx-.045,fy,fx+.045,fy+o["pole_height"],"#886a48",INK,.4,zorder=85)
            ax.plot([fx,fx+.3],[fy+o["pole_height"]]*2,color="#886a48",lw=1,zorder=85)
            ax.plot([fx,x],[fy+o["pole_height"],y],color="#886a48",lw=.7,zorder=85)
            if code in ["P2","P4"]:continue
            text={"P1":"P1 / P2","P3":"P3 / P4"}.get(code,code)
            label(ax,x-.6 if code=="P1" else x,y+1.12,text,9,color=color,zorder=96)
        elif o["kind"]=="lantern":
            fx,fy,fz=o["fixture_position"]
            ax.plot([fx,x],[fy,y],color="#886a48",lw=.7,zorder=85)
            ax.add_patch(Ellipse((x,y),.28,.38,facecolor="#e5b864",edgecolor="#886a48",lw=.5,zorder=86))
            label(ax,x,y+.5,code,8,color=color,zorder=96)
        elif code=="C1":
            ax.plot([x,4.5],[y,3],color=color,lw=.7,zorder=95)
            label(ax,4.6,3.1,"C1 桥心冷光",10,color=color,ha="left",zorder=96)
        else:label(ax,x,y-.5,code,8,color=color,zorder=96)
        ax.plot(x,y,marker="D" if o["kind"]=="lantern" else "*",markersize=5 if o["kind"]=="lantern" else 14 if code=="C1" else 9,color=color,markeredgecolor=PAPER,markeredgewidth=.5,zorder=95)


def lighting_legend(ax):
    ax.axis("off");y=1
    label(ax,0,y,"灯位索引 · X / Y / Z",13,ha="left",va="top",transform=ax.transAxes);y-=.046
    for o in DATA["lights"]:
        x,h,z=o["position"];color="#438bb4" if o["diagram_id"]=="C1" else "#b87829"
        label(ax,0,y,f"{o['diagram_id']} {o['label']}  {x:g} / {h:g} / {z:g}",9,ha="left",va="top",color=color,transform=ax.transAxes);y-=.038
    y-=.022
    for title,lines in [
        ("P6 码头暖灯",["位于木板西侧靠坡道的角落","灯柱脚点：−12.78 / −0.32 / 4.9","光源高度：高于木板 2.2 m","暖光半径 4.5 m；关闭阴影"]),
        ("读图与性能设计",["星点为光源，菱形为灯笼光源","空心小圈为灯柱脚点","C1 / P6 虚圈为范围示意","表中 Y 为光源高度，单位米","共 14 灯；复用原码头路灯编号","灯数和投影灯数均不增加"])
    ]:
        label(ax,0,y,title,12,ha="left",va="top",transform=ax.transAxes);y-=.042
        for line in lines:
            label(ax,0,y,line,9,ha="left",va="top",color=SOFT,transform=ax.transAxes);y-=.031
        y-=.018


def background_top(ax,layer):
    for obj in DATA["background_buildings"]:
        if obj["layer"]!=layer:continue
        x,_,z=obj["position"];x0,z0,x1,z1=roof_bounds(obj)
        rect(ax,x0,z0,x1,z1,"#c4d2cb" if layer=="near_town" else "#d9dfd7",SOFT,.8,zorder=2)
        ax.plot([x0+.2,x1-.2],[(z0+z1)/2]*2,color=SOFT,lw=.6,zorder=3)
        label(ax,x,z-.5,obj["id"],11,zorder=4)
        label(ax,x,z+.8,f"{x:g} / {z:g}",8,color=SOFT,zorder=4)
    for obj in DATA["background_trees"]:
        if obj["layer"]!=layer:continue
        x,_,z=obj["position"];s=obj["scale"]
        ax.add_patch(Ellipse((x,z),4.8*s,2.4*s,facecolor="#d4dfcd",edgecolor=PLANT,lw=.6,zorder=2))
        ax.add_patch(Circle((x,z),.13,facecolor=PLANT,zorder=3))
        label(ax,x,z+1.7*s,obj["id"],8,color=PLANT,zorder=4)


def top(ax,full=False,lighting_focus=False):
    ax.set_facecolor(PAPER);ax.set_xlim(-31,31);ax.set_ylim(15.7,-18.6 if lighting_focus else -53 if full else -35.8);ax.set_aspect("equal")
    ax.set_xticks(np.arange(-25,26,5));ax.set_yticks(([] if lighting_focus else [-50,-40,-30,-20] if full else [-30,-20])+[-16,-10,-5,0,5,10,14]);ax.tick_params(labelsize=9,length=0,pad=6,colors=SOFT)
    ax.set_xticks(np.arange(-26,27,1),minor=True);ax.set_yticks(np.arange(-16,15,1),minor=True)
    ax.tick_params(which="minor",length=0);ax.grid(which="minor",color="#dcded5",lw=.35,zorder=0)
    for s in ax.spines.values():s.set_visible(False)
    if not lighting_focus:
        rect(ax,-28,-34,28,-16,"#edf0e6","none",zorder=0)
        background_top(ax,"near_town")
        label(ax,6,-31.3,"近镇背景 · 错落房屋 + 树群",12,color=SOFT,zorder=4)
        label(ax,6,-29.5,"B1–B6 / 无碰撞 / 不投影",9,color=SOFT,zorder=4)
    if full:
        rect(ax,-31,-50,31,-36,"#eff0e9","none",zorder=0)
        background_top(ax,"far_town")
        label(ax,0,-49.3,"远镇背景 · F1–F4；后接山、云与夜空",11,color=SOFT)
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
    label(ax,1.2,-.4,"石桥",10,zorder=13)
    dock=DATA["dock"];dx,dy,dz=dock["center"];dw,dl=dock["deck_size_xz"]
    x0,x1=dx-dw/2,dx+dw/2;z0,z1=dz-dl/2,dz+dl/2
    rect(ax,x0,z0,x1,z1,"#ac845d",INK,1,zorder=8)
    for z in np.linspace(z0+.05,z1-.05,15):ax.plot([x0+.05,x1-.05],[z,z],color="#7c644d",lw=.5,zorder=9)
    r0,r1=dock["ramp_z"];rw=dock["ramp_width"]
    rect(ax,dx-rw/2,r0,dx+rw/2,r1,"#c5a27a",INK,.7,zorder=9)
    ax.annotate("",xy=(dx,dz-.7),xytext=(dx,r1-.1),arrowprops=dict(arrowstyle="->",color="#fff7df",lw=1.2),zorder=10)
    label(ax,dx-3.1,dz,"前岸木码头\nY=−0.32",10,zorder=10)
    ax.plot([dx-2,x0],[dz,dz],color=INK,lw=.7,zorder=10)
    label(ax,dx-2.2,6,"缓坡接前岸",9,color=SOFT,ha="right",zorder=10)
    boat=DATA["boat"];x,_,z=boat["center"];b=boat["model_bounds"]
    bx0,bx1=x+b["min"][2],x+b["max"][2];bz0,bz1=z-b["max"][0],z-b["min"][0]
    ax.add_patch(Polygon([(bx0,z),(bx0+.6,bz0),(bx1-.6,bz0),(bx1,z),(bx1-.6,bz1),(bx0+.6,bz1)],facecolor="#806750",edgecolor=INK,lw=1,zorder=7))
    label(ax,x,z,"泊船",10,color="#fff4db",zorder=8);ax.plot([x1,bx0],[dz-.2,z],color=INK,lw=.8,zorder=11)
    for tree_id,(x,y,z) in zip(DATA["willow_ids"],DATA["willows"]):
        ax.add_patch(Ellipse((x,z),4.8,2.4,facecolor="#cedbd0",edgecolor=PLANT,lw=.8,linestyle=(0,(3,3)),zorder=4))
        ax.add_patch(Circle((x,z),.19,facecolor=INK,zorder=5));label(ax,x,z-.35 if z<0 else z+.35,"柳"+tree_id[1:],8,color=PLANT,zorder=8)
    ax.plot([-24.3,24.3],[-2.4,-2.4],color=LINE,lw=2,linestyle=(0,(5,3)),zorder=14)
    ax.plot([-24.3,24.3],[8.5,8.5],color=LINE,lw=2,linestyle=(0,(5,3)),zorder=14)
    ax.plot([1.2,1.2],[-2.4,-1.9],color=LINE,lw=2,zorder=14);ax.plot([1.2,1.2],[6.9,8.5],color=LINE,lw=2,zorder=14)
    ax.plot([dx,dx],[8.5,r1+.2],color=LINE,lw=1.5,linestyle=(0,(3,2)),zorder=14)
    for index,npc in enumerate(DATA["npcs"],1):
        x,_,z=npc["position"];ax.add_patch(Circle((x,z),.31,facecolor="#bc5a38",edgecolor=PAPER,lw=1,zorder=16));label(ax,x,z,str(index),8,color="white",zorder=17)
    label(ax,13.5,-2.4,"后岸街 · 连续通行",10,bbox=dict(facecolor=ROAD,edgecolor="none",pad=2),zorder=15)
    label(ax,12,8.5,"前岸步道 · 镜头跟随横移",11,bbox=dict(facecolor=ROAD,edgecolor="none",pad=2),zorder=15)
    label(ax,14,3,"横向河道  /  Z=2.5",12,color="#366e7c",zorder=6)
    label(ax,1.2,-10,"桥轴留空\n6.8 m",11,color=SOFT,zorder=9)
    label(ax,-9.5,-4.3,"酒肆院坪",9,color="#517e69",zorder=10)
    label(ax,-10,-15,"后巷 1.0 m",8,color=SOFT,zorder=10)
    label(ax,0,-18.3 if lighting_focus else -52 if full else -35,"灯位俯视图 · 点为光源，空心圈为灯柱脚点" if lighting_focus else "俯视图 · 坐标与屋檐范围对应摆放数据",14,ha="center")
    dim(ax,(-26,-17.1),(26,-17.1),"可行走地图宽 52.0 m")
    dim(ax,(-27.5,-16),(-27.5,14),"30.0 m",True)
    dim(ax,(27.1,-.1),(27.1,5.1),"河宽 5.2 m",True)
    dim(ax,(-25.8,-3.8),(-25.8,-1),"2.8 m",True)
    dim(ax,(-25.8,6.4),(-25.8,10.6),"4.2 m",True)
    dim(ax,(3.7,-1.7),(3.7,6.7),"桥跨度 8.4 m",True)
    dim(ax,(-.2,7.8),(2.6,7.8),"2.8 m")
    ax.annotate("",xy=(23.5,-13.8),xytext=(23.5,-10.2),arrowprops=dict(arrowstyle="->",color=INK,lw=1.5));label(ax,23.5,-14.4,"−Z 后岸",10)
    ax.annotate("",xy=(21,6),xytext=(21,10.8),arrowprops=dict(arrowstyle="->",color=INK,lw=1.3));label(ax,20.5,11.4,"正视方向",9,zorder=20)
    top_lights(ax)
    ax.set_xlabel("X / 米   左负右正",fontproperties=FONT,fontsize=10,color=SOFT,labelpad=5)


def far_top(ax):
    ax.set_facecolor("#eff0e9");ax.set_xlim(-31,31);ax.set_ylim(-35,-51);ax.set_aspect("equal")
    background_top(ax,"far_town")
    ax.set_xticks([-25,0,25]);ax.set_yticks([-50,-40,-36]);ax.tick_params(labelsize=8,length=0,colors=SOFT)
    for s in ax.spines.values():s.set_visible(False)
    ax.set_title("远镇分图 · 同一 X/Z 坐标",fontproperties=FONT,fontsize=12,color=INK,pad=10)


def elevation_tree(ax,obj,base,front=False):
    x,y,z=obj["position"];s=obj.get("scale",1)
    color=PLANT if front else "#a9bda6";face="#d1ddce" if front else "#dce3d5"
    rect(ax,x-.10*s,y,x+.10*s,y+3.8*s,color,"none",zorder=base)
    ax.add_patch(Ellipse((x,y+4.2*s),4.8*s,3.7*s,facecolor=face,edgecolor=color,lw=.6,zorder=base))
    for dx in [-1.8,-1,-.2,.6,1.4]:ax.plot([x+dx*s,x+(dx+.1)*s],[y+5*s,y+(1.6+abs(dx)*.3)*s],color=color,lw=.6,zorder=base+.1)


def elevation_building(ax,obj,base,background=False):
    x=obj["position"][0];b=obj["model_bounds"];x0=x+b["min"][0];x1=x+b["max"][0];height=b["max"][1]
    is_stall=obj["id"].startswith("S");is_tav=obj["id"]=="T1";far=obj.get("layer")=="far_town"
    eave=height-(.35 if is_stall else .75)
    wall="#e8e7db" if far else "#d9dfcf" if background else "#cfb595" if is_tav else "#e0d8c4"
    roof="#d4ddd4" if far else "#afc3b8" if background else STALL if is_stall else TAVERN if is_tav else ROOF
    edge=SOFT if background else INK
    rect(ax,x0+.3,0,x1-.3,eave,wall,edge,.7,zorder=base)
    ax.add_patch(Polygon([(x0,eave),(x0+.65,eave+.55*(height-eave)),(x,height),(x1-.65,eave+.55*(height-eave)),(x1,eave)],facecolor=roof,edgecolor=edge,lw=.9,zorder=base+.1))
    if background:
        for xx in [x-1.2,x+1.2]:rect(ax,xx-.28,.9,xx+.28,1.5,"#bccab5",edge,.4,zorder=base+.2)
        return
    if is_stall:
        for xx in [x0+.22,x1-.22]:rect(ax,xx-.045,0,xx+.045,eave,"#8c6747",INK,.3,zorder=base+.2)
        rect(ax,x0+.25,.72,x1-.25,1.03,STALL,INK,.6,zorder=base+.2)
    else:
        rect(ax,x-.48,0,x+.48,1.65,"#725743",INK,.7,zorder=base+.2)
        for xx in [x-1.4,x+1.4]:rect(ax,xx-.36,.95,xx+.36,1.65,"#dcbb70",INK,.6,zorder=base+.2)
        if is_tav:
            ax.plot([x0+.2,x1-.2],[2.72,2.72],color=INK,lw=1,zorder=base+.2)
            for xx in [x-1.6,x,x+1.6]:rect(ax,xx-.4,3.25,xx+.4,4.15,"#dcbb70",INK,.6,zorder=base+.2)
    label(ax,x,height+.55,obj["id"]+"  "+obj["label"],10,zorder=90)


def elevation(ax):
    ax.set_xlim(-29,29);ax.set_ylim(-1.6,8.5);ax.set_aspect("equal");ax.set_facecolor(PAPER)
    ax.set_xticks(np.arange(-25,26,5));ax.set_yticks([-.62,0,2,4,6]);ax.tick_params(labelsize=9,length=0,colors=SOFT)
    for s in ax.spines.values():s.set_visible(False)
    ax.axhline(0,color=INK,lw=1);ax.axhline(-.62,color="#6597a3",lw=1)
    rect(ax,-26,-.9,26,-.62,WATER,"none")
    scene=[(o,False) for o in DATA["background_buildings"]]+[(o,True) for o in DATA["background_trees"]]+[(o,False) for o in DATA["objects"]]+[({"position":p},True) for p in DATA["willows"] if p[2]<0]
    for i,(obj,tree) in enumerate(sorted(scene,key=lambda pair:pair[0]["position"][2])):
        base=3+i
        if tree:elevation_tree(ax,obj,base,front="layer" not in obj)
        else:elevation_building(ax,obj,base,background="layer" in obj)
    dock=DATA["dock"];dx,dy,dz=dock["center"];dw=dock["deck_size_xz"][0]
    rect(ax,dx-dw/2,dy-.16,dx+dw/2,dy,"#aa815c",INK,.7,zorder=73)
    boat=DATA["boat"];x=boat["center"][0];b=boat["model_bounds"]
    ax.add_patch(Polygon([(x+b["min"][2],-.25),(x+b["min"][2]+.5,-.6),(x+b["max"][2]-.5,-.6),(x+b["max"][2],-.25)],facecolor="#806750",edgecolor=INK,lw=.8,zorder=73))
    rect(ax,x-.8,-.24,x+.8,.48,"#aa815c",INK,.6,zorder=73)
    rect(ax,-.2,-.62,2.6,.6,"#b6b7ab",INK,.8,zorder=70)
    for xx in [-.43,2.83]:rect(ax,xx-.11,.3,xx+.11,1.63,"#a0a99f",INK,.6,zorder=71)
    ax.plot([-.35,2.75],[1.63,1.63],color=SOFT,lw=.7,zorder=71)
    for index,npc in enumerate(DATA["npcs"],1):
        x,y,z=npc["position"];ax.add_patch(Circle((x,y+1.45),.13,facecolor="#bc5a38",edgecolor=INK,lw=.4,zorder=75));rect(ax,x-.15,y,x+.15,y+1.3,"#bc5a38",INK,.4,zorder=75)
    for p in DATA["willows"]:
        if p[2]>0:elevation_tree(ax,{"position":p},80,front=True)
    elevation_lights(ax)
    label(ax,12,7.8,"正视图 · 从前岸 +Z 看向后岸 −Z",14)
    label(ax,12,6.8,"浅色为近镇/远镇；屋高按模型，门窗与树冠为示意",9,color=SOFT)
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
    radius=DATA["willow_policy"]["trunk_radius"]
    for i,(x,y,z) in enumerate(DATA["willows"],1):
        margin=(-1,-.1) if z<0 else (5.1,6.4)
        if not (margin[0]<=z-radius and z+radius<=margin[1]):failures.append(f"willow {i}: trunk outside bank margin")
        if -.445-radius<x<2.845+radius:failures.append(f"willow {i}: bridge approach blocked")
        dock=DATA["dock"];dx,_,dz=dock["center"]
        if z>0 and dx-dock["ramp_width"]/2-radius<x<dx+dock["ramp_width"]/2+radius:failures.append(f"willow {i}: dock approach blocked")
    if len(DATA["willows"])!=5 or DATA["willow_ids"]!=["L1","L2","L3","L4","L6"]:failures.append("expected five bank willows, retaining IDs after removal of L5")
    if [-8,0,5.75] in DATA["willows"]:failures.append("tavern foreground willow must be removed")
    dock=DATA["dock"];dx,dy,dz=dock["center"];rw=dock["ramp_width"];r0,r1=dock["ramp_z"]
    if not np.allclose([dx,dy,dz,r0,r1],[-12,-.32,3.8,5.3,6.6]):failures.append("dock and ramp must mirror R2 across Z=2.5")
    street=DATA["streets"]["front"];clear=street["z"][1]-max(street["z"][0],r1)
    if clear<4-1e-8 or not np.isclose(clear,dock["approach_clear_street_width"]):failures.append("front walk at dock must retain 4m clear width")
    if not np.isclose(r0,dz+dock["deck_size_xz"][1]/2) or not street["z"][0]<=r1<street["z"][1]:failures.append("ramp must join dock to front street")
    boat=DATA["boat"];bx,by,bz=boat["center"];bb=boat["model_bounds"]
    boat_bounds=(bx+bb["min"][2],bz-bb["max"][0],bx+bb["max"][2],bz-bb["min"][0])
    if not DATA["river"]["z"][0]<boat_bounds[1]<boat_bounds[3]<DATA["river"]["z"][1]:failures.append("boat must remain in river")
    if boat_bounds[0]<=dx+dock["deck_size_xz"][0]/2:failures.append("boat must not overlap dock")
    npc=next(n for n in DATA["npcs"] if n["id"]=="boatman");nx,ny,nz=npc["position"]
    if not (abs(nx-dx)<dock["deck_size_xz"][0]/2 and abs(nz-dz)<dock["deck_size_xz"][1]/2 and np.isclose(ny,dy)):failures.append("boatman must stand on new dock")
    bg=DATA["background_buildings"]
    for o in bg+DATA["background_trees"]:
        front=roof_bounds(o)[3] if "model_bounds" in o else o["position"][2]+1.2*o["scale"]
        if front>=-16 or o["collision"] or o["cast_shadow"]:failures.append(o["id"]+": invalid decorative background policy")
    for i,a in enumerate(bg):
        aa=roof_bounds(a)
        for b in bg[i+1:]:
            bb=roof_bounds(b)
            if max(aa[0],bb[0])<min(aa[2],bb[2]) and max(aa[1],bb[1])<min(aa[3],bb[3]):failures.append(a["id"]+"/"+b["id"]+": background roof overlap")
    cool=next(o for o in DATA["lights"] if o["diagram_id"]=="C1")
    if cool["position"]!=[1.2,2.4,2.5]:failures.append("cool light must be at bridge center, 1.8m above highest deck")
    if {o["id"] for o in DATA["lights"] if o["kind"]=="broad"}!={"broad_cloth_cool","broad_tavern_warm"}:failures.append("existing broad-light IDs must be retained")
    source=json.loads((ROOT/"resources/ancient-canal/layout.json").read_text())
    expected={o["id"] for o in source["streetlamps"]+source["broad_lights"]}|{"lantern_"+str(i) for i in range(sum(o["id"]=="lantern" for o in source["models"]))}
    if len(DATA["lights"])!=14 or {o["id"] for o in DATA["lights"]}!=expected:failures.append("all fourteen existing lights must be identified without new IDs")
    if len({o["diagram_id"] for o in DATA["lights"]})!=14:failures.append("diagram light IDs must be unique")
    for o in DATA["lights"]:
        if "fixture_position" in o and not np.allclose(o["position"],np.array(o["fixture_position"])+o["light_offset"]):failures.append(o["id"]+": fixture/emitter offset mismatch")
        if o["kind"]=="streetlamp":
            fx,fy,fz=o["fixture_position"];radius=o["collision_radius"]
            if -.445-radius<fx<2.845+radius and -1.84-radius<fz<6.84+radius:failures.append(o["id"]+": pole overlaps bridge")
            if o["diagram_id"]!="P6" and min(abs(fz+2.4),abs(fz-8.5))<radius+.3:failures.append(o["id"]+": pole blocks main street centerline")
    dock_light=next(o for o in DATA["lights"] if o["diagram_id"]=="P6")
    fx,fy,fz=dock_light["fixture_position"];radius=dock_light["collision_radius"]
    if not (dx-1<=fx-radius<fx+radius<=dx+1 and dz-1.5<=fz-radius<fz+radius<=dz+1.5 and np.isclose(fy,dy)):failures.append("dock lamp pole must stand entirely on dock")
    if fz+radius>=r0:failures.append("dock lamp must clear ramp")
    if dock_light["cast_shadow"] or dock_light["range_m"]!=4.5:failures.append("dock lamp must be warm local light with 4.5m range and no shadow")
    sys.path.insert(0,str(ROOT/"tools"));from feature_fingerprint import fingerprint
    before=json.loads((HERE/"runtime-before.json").read_text());unchanged=fingerprint(ROOT)["sha256"]==before["runtime_fingerprint"]
    report={"passed":not failures and unchanged,"failures":failures,"runtime_unchanged":unchanged,"roof_bounds":bounds,"background_roof_bounds":{o["id"]:roof_bounds(o) for o in bg},"dock_approach_clear_width":clear,"boat_bounds_xz":boat_bounds,"checks":["7 measured roof envelopes inside map","no foreground or background roof envelope overlap","streets and bridge alley clear of roofs","four 1.6m entrance corridors clear of other roofs","five willow trunks inside bank margins and clear of bridge/dock approaches; L5 removed","dock and ramp mirrored to front bank across Z=2.5","ramp joins front street; 4m continuous clear width","boat inside river and clear of dock; boatman stands on new deck","background houses and trees outside playable boundary; collision and shadows disabled","cool light at bridge center; two existing control IDs retained","runtime fingerprint unchanged"],"scope":"Static layout geometry only. Collision and in-game visibility will be validated after user approval and placement."}
    report["checks"] += ["all 14 existing lamp control IDs retained and marked","fixture origins and light emitters match offsets","streetlamp poles clear bridge and street centerlines","dock lamp pole inside wood deck and clear of ramp; 4.5m local light without shadow"]
    report["lighting"]={"lamp_count":len(DATA["lights"]),"additional_light_nodes":0,"dock_lamp":dock_light}
    (HERE/"review-checks.json").write_text(json.dumps(report,indent=2)+"\n")
    assert report["passed"],report


def main():
    review_checks()
    fig=plt.figure(figsize=(24,24),facecolor=PAPER)
    fig.text(.045,.965,"Ancient 河街建筑摆放图",fontproperties=FONT,fontsize=28,color=INK)
    fig.text(.045,.938,"R4 审阅稿  /  2026-10-08  /  全部灯位标注 · 新码头暖灯 · 保留 R3 建筑与树木摆位",fontproperties=FONT,fontsize=12,color=SOFT)
    top(fig.add_axes([.04,.305,.75,.61]));elevation(fig.add_axes([.04,.105,.75,.16]))
    lighting_legend(fig.add_axes([.815,.43,.17,.485]))
    far_top(fig.add_axes([.815,.30,.17,.105]))
    side_section(fig.add_axes([.815,.12,.17,.11]))
    fig.text(.045,.068,"审阅重点：C1 桥心冷光、W1 酒肆暖光、P6 码头暖灯；其余 P 为路灯，E 为檐下与门口灯笼。",fontproperties=FONT,fontsize=12,color=INK)
    fig.text(.045,.030,"本图与坐标文件一一对应。确认后依此摆放；此阶段未改运行场景。平面、正视及剖面为设计图，非 GPU 渲染验收。",fontproperties=FONT,fontsize=10,color=SOFT)
    for suffix in ["png","svg","pdf"]:
        metadata={"Creator":"Ancient layout review","CreationDate":datetime(2026,10,8,tzinfo=timezone.utc)} if suffix=="pdf" else None
        fig.savefig(HERE/("layout-review."+suffix),dpi=150,facecolor=PAPER,metadata=metadata)
    plt.close(fig)
    for name,fn,size in [("top-view",top,(18,16)),("front-view",elevation,(20,5)),("full-top-view",lambda ax:top(ax,full=True),(18,21)),("far-town",far_top,(16,5))]:
        f=plt.figure(figsize=size,facecolor=PAPER);fn(f.add_axes([.05,.08,.9,.85]));f.savefig(HERE/(name+".png"),dpi=160,facecolor=PAPER);plt.close(f)
    with (HERE/"placement.csv").open("w") as stream:
        writer=csv.writer(stream);writer.writerow(["id","asset","label","x_m","y_m","z_m","yaw_deg","layer","collision","cast_shadow","scale_x","scale_y","scale_z"])
        for o in DATA["objects"]:writer.writerow([o["id"],o["asset"],o["label"],*o["position"],o["yaw_deg"],"playable",True,"existing",1,1,1])
        for o in DATA["background_buildings"]+DATA["background_trees"]:writer.writerow([o["id"],o["asset"],o.get("label","背景树群"),*o["position"],o.get("yaw_deg",0),o["layer"],o["collision"],o["cast_shadow"],*o.get("scale_xyz",[o.get("scale",1)]*3)])
        for tree_id,p in zip(DATA["willow_ids"],DATA["willows"]):writer.writerow([tree_id,"willow","河岸柳树",*p,0,"rear_bank" if p[2]<0 else "front_bank",True,p[2]>0,1,1,1])
        for o in DATA["lights"]:writer.writerow([o["diagram_id"],"OmniLight3D",o["label"],*o["position"],0,"lighting",False,"existing",1,1,1])
        for i,o in enumerate(DATA["npcs"],1):writer.writerow(["NPC"+str(i),o["id"],o["label"],*o["position"],0,"playable","existing","existing",1,1,1])
        for obj_id,key,asset in [("D1","dock","dock"),("BO1","boat","boat"),("BR1","bridge","low_bridge")]:
            o=DATA[key];writer.writerow([obj_id,asset,asset,*o["center"],o.get("yaw_deg",0),"playable","existing","existing",1,1,1])
    lighting_figure=plt.figure(figsize=(24,15),facecolor=PAPER)
    lighting_figure.text(.045,.96,"Ancient R4 灯位摆放图",fontproperties=FONT,fontsize=26,color=INK)
    top(lighting_figure.add_axes([.04,.08,.75,.82]),lighting_focus=True)
    lighting_legend(lighting_figure.add_axes([.815,.10,.17,.80]))
    lighting_figure.savefig(HERE/"lighting-plan.png",dpi=150,facecolor=PAPER);plt.close(lighting_figure)
    with (HERE/"lights.csv").open("w") as stream:
        writer=csv.writer(stream);writer.writerow(["diagram_id","control_id","label","kind","light_x","light_y","light_z","fixture_x","fixture_y","fixture_z","range_m","cast_shadow","red","green","blue"])
        for o in DATA["lights"]:writer.writerow([o["diagram_id"],o["id"],o["label"],o["kind"],*o["position"],*o.get("fixture_position",["","",""]),o["range_m"],o["cast_shadow"],*o["tint_rgba"][:3]])
    print("REVIEW_DRAWINGS_READY: top/front/combined PNG, SVG, PDF, coordinates and geometry checks")

if __name__=="__main__":main()

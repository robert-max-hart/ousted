#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_icons.py
#     Regenerates the SVG files in assets/icons/ui (18 px button glyphs)
#     and assets/icons/stock (22 px top-bar icons, with a dark outline).
#     Shapes are listed per icon in 0..1 coordinates (polygons, rectangles,
#     ellipses, thick lines). Edit a shape here and run:
#         python3 tools/make_icons.py
#     then `godot --headless --path . --import` to refresh the imports.
#     The SVGs are the assets: editing them by hand, or dropping a PNG of
#     the same name beside one, also works (see scripts/ui/asset_icons.gd);
#     running this script overwrites the SVGs it knows.
# ----------------------------------------------------------------
import math, os
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "icons")
os.makedirs(OUT + "/ui", exist_ok=True)
os.makedirs(OUT + "/stock", exist_ok=True)
def hx(c):
    return "#%02x%02x%02x" % tuple(round(v*255) for v in c[:3])
def op(c):
    return c[3] if len(c)>3 else 1.0
S=100.0
def f(v): return "%.2f" % (v*S)
class Icon:
    def __init__(s): s.items=[]
    def P(s,pts,c): s.items.append(("poly",pts,c))
    def R(s,x,y,w,h,c): s.items.append(("poly",[(x,y),(x+w,y),(x+w,y+h),(x,y+h)],c))
    def E(s,cx,cy,rx,ry,c): s.items.append(("ell",(cx,cy,rx,ry),c))
    def L(s,a,b,w,c):
        dx,dy=b[0]-a[0],b[1]-a[1]; n=math.hypot(dx,dy); ox,oy=-dy/n*w/2,dx/n*w/2
        s.items.append(("poly",[(a[0]+ox,a[1]+oy),(b[0]+ox,b[1]+oy),(b[0]-ox,b[1]-oy),(a[0]-ox,a[1]-oy)],c))
    def RING(s,cx,cy,rx,ry,w,c): s.items.append(("ring",(cx,cy,rx,ry,w),c))
    def shape(s,it,fill=None,stroke=None,sw=0):
        kind,d,c=it
        st=""
        if stroke: st=' stroke="%s" stroke-width="%s" stroke-linejoin="round"'%(stroke,f(sw))
        if kind=="poly":
            pts=" ".join("%s,%s"%(f(x),f(y)) for x,y in d)
            return '<polygon points="%s" fill="%s"%s/>'%(pts,fill or hx(c),st)
        if kind=="ell":
            cx,cy,rx,ry=d
            return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"%s/>'%(f(cx),f(cy),f(rx),f(ry),fill or hx(c),st)
        cx,cy,rx,ry,w=d
        return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="none" stroke="%s" stroke-width="%s"/>'%(f(cx),f(cy),f(rx),f(ry),hx(c),f(w))
    def svg(s,size,outline=None):
        o=['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 100 100">'%(size,size)]
        if outline:
            col,w=outline
            for it in s.items:
                if it[0]=="ring": continue
                o.append(s.shape(it,fill=col,stroke=col,sw=w))
        for it in s.items:
            o.append(s.shape(it))
        o.append("</svg>")
        return "\n".join(o)+"\n"

LIGHT=(0.95,0.9,0.78);MID=(0.72,0.64,0.5);DARK=(0.46,0.4,0.3);GOLD=(0.97,0.78,0.16)
GREEN=(0.5,0.8,0.38);BLUE=(0.45,0.72,0.95);RED=(0.92,0.38,0.3);BROWN=(0.66,0.46,0.26)
V=lambda x,y:(x,y)
ui={}
def new(n): i=Icon(); ui[n]=i; return i
i=new("arrow"); i.P([V(.24,.1),V(.24,.8),V(.42,.64),V(.56,.92),V(.68,.86),V(.54,.58),V(.78,.56)],LIGHT)
i=new("axe"); i.L(V(.24,.9),V(.7,.2),.12,BROWN); i.P([V(.46,.14),V(.84,.1),V(.9,.46),V(.66,.4),V(.52,.34)],LIGHT); i.P([V(.46,.14),V(.84,.1),V(.8,.22),V(.52,.26)],MID)
i=new("basket"); i.RING(.5,.46,.28,.3,.06,MID); i.P([V(.1,.5),V(.9,.5),V(.78,.9),V(.22,.9)],LIGHT)
i.L(V(.3,.56),V(.34,.86),.05,DARK); i.L(V(.5,.56),V(.5,.86),.05,DARK); i.L(V(.7,.56),V(.66,.86),.05,DARK)
i=new("sapling"); i.R(.46,.5,.08,.4,BROWN); i.E(.3,.38,.22,.14,GREEN); i.E(.7,.3,.22,.14,GREEN); i.E(.5,.16,.12,.12,GREEN); i.R(.2,.88,.6,.06,MID)
i=new("trench"); i.P([V(.06,.34),V(.94,.34),V(.8,.84),V(.2,.84)],BROWN); i.P([V(.2,.34),V(.8,.34),V(.72,.7),V(.28,.7)],BLUE); i.L(V(.3,.5),V(.7,.5),.05,LIGHT)
i=new("hammer"); i.L(V(.3,.92),V(.58,.3),.12,BROWN); i.R(.22,.1,.7,.26,LIGHT); i.R(.22,.1,.7,.08,MID)
i=new("cross"); i.L(V(.2,.2),V(.8,.8),.16,RED); i.L(V(.8,.2),V(.2,.8),.16,RED)
i=new("house"); i.R(.2,.46,.6,.42,LIGHT); i.P([V(.08,.5),V(.5,.12),V(.92,.5)],BROWN); i.R(.42,.62,.16,.26,DARK)
i=new("crate"); i.R(.12,.28,.76,.62,BROWN); i.R(.12,.28,.76,.1,LIGHT); i.L(V(.16,.42),V(.84,.86),.07,DARK); i.L(V(.84,.42),V(.16,.86),.07,DARK)
i=new("wheat"); i.L(V(.5,.94),V(.5,.3),.06,MID)
for y in (.12,.28,.44): i.E(.36,y+.1,.1,.07,GOLD); i.E(.64,y+.1,.1,.07,GOLD)
i.E(.5,.12,.08,.1,GOLD)
i=new("anvil"); i.P([V(.06,.28),V(.94,.28),V(.78,.5),V(.66,.5),V(.66,.64),V(.8,.86),V(.2,.86),V(.34,.64),V(.34,.5),V(.26,.5)],LIGHT); i.R(.06,.28,.88,.08,MID)
i=new("flag"); i.R(.22,.08,.07,.84,LIGHT); i.P([V(.29,.12),V(.86,.26),V(.29,.5)],GOLD)
i=new("people"); i.E(.34,.3,.14,.16,LIGHT); i.P([V(.08,.86),V(.12,.58),V(.26,.5),V(.42,.5),V(.56,.58),V(.6,.86)],LIGHT)
i.E(.7,.34,.12,.14,MID); i.P([V(.58,.86),V(.62,.6),V(.72,.54),V(.82,.58),V(.92,.66),V(.94,.86)],MID)
i=new("person"); i.E(.5,.28,.17,.2,LIGHT); i.P([V(.16,.9),V(.2,.62),V(.36,.5),V(.64,.5),V(.8,.62),V(.84,.9)],LIGHT)
i=new("scroll"); i.R(.2,.12,.6,.76,LIGHT)
for y in (.26,.42,.58,.74): i.R(.3,y,.4,.05,DARK)
i=new("tablet"); i.P([V(.18,.88),V(.18,.26),V(.5,.08),V(.82,.26),V(.82,.88)],LIGHT); i.L(V(.34,.5),V(.66,.5),.06,DARK); i.L(V(.34,.68),V(.66,.68),.06,DARK)
i=new("drop"); i.P([V(.5,.06),V(.84,.58),V(.5,.58),V(.16,.58)],BLUE); i.E(.5,.62,.34,.3,BLUE); i.E(.38,.56,.07,.1,LIGHT)
i=new("slope"); i.P([V(.06,.86),V(.94,.86),V(.94,.2)],MID); i.P([V(.06,.86),V(.62,.86),V(.62,.46)],LIGHT)
i=new("soil"); i.R(.08,.6,.84,.3,BROWN); i.R(.08,.6,.84,.07,MID); i.R(.47,.3,.06,.34,GREEN); i.E(.34,.3,.16,.1,GREEN); i.E(.66,.24,.16,.1,GREEN)
i=new("pick"); i.L(V(.26,.92),V(.68,.3),.11,BROWN); i.P([V(.1,.4),V(.3,.14),V(.62,.1),V(.9,.3),V(.78,.32),V(.58,.24),V(.36,.28),V(.2,.46)],LIGHT)
i=new("book"); i.P([V(.08,.2),V(.48,.28),V(.48,.88),V(.08,.8)],LIGHT); i.P([V(.92,.2),V(.52,.28),V(.52,.88),V(.92,.8)],MID); i.L(V(.16,.38),V(.4,.44),.05,DARK); i.L(V(.16,.54),V(.4,.6),.05,DARK)
i=new("fish"); i.E(.44,.5,.34,.22,BLUE); i.P([V(.7,.5),V(.94,.26),V(.94,.74)],BLUE); i.E(.28,.44,.04,.05,DARK)
i=new("spool"); i.R(.2,.14,.6,.12,LIGHT); i.R(.2,.74,.6,.12,LIGHT); i.R(.28,.26,.44,.48,RED); i.L(V(.28,.38),V(.72,.34),.05,(.7,.25,.2)); i.L(V(.28,.54),V(.72,.5),.05,(.7,.25,.2))

stock={}
def sn(n): i=Icon(); stock[n]=i; return i
i=sn("wood"); i.R(.12,.34,.62,.36,(.52,.34,.18)); i.R(.12,.34,.62,.08,(.64,.44,.24)); i.E(.74,.52,.17,.2,(.82,.64,.4)); i.E(.74,.52,.1,.12,(.68,.48,.28)); i.E(.74,.52,.04,.05,(.82,.64,.4))
i=sn("firewood")
for r in ([.1,.62],[.42,.62],[.26,.34]):
    i.R(r[0],r[1],.32,.26,(.74,.5,.26)); i.R(r[0],r[1],.32,.07,(.88,.66,.38)); i.E(r[0]+.32,r[1]+.13,.05,.13,(.9,.74,.5))
i=sn("coal"); i.P([V(.1,.78),V(.18,.46),V(.42,.36),V(.56,.6),V(.5,.82)],(.2,.2,.23)); i.P([V(.42,.8),V(.5,.3),V(.74,.2),V(.9,.5),V(.84,.82)],(.28,.28,.32)); i.R(.55,.3,.1,.06,(.62,.64,.72)); i.R(.2,.5,.07,.05,(.5,.52,.6))
i=sn("stone"); i.P([V(.1,.78),V(.14,.48),V(.36,.26),V(.68,.24),V(.9,.5),V(.9,.78)],(.55,.55,.52)); i.P([V(.14,.48),V(.36,.26),V(.68,.24),V(.5,.44)],(.72,.72,.68)); i.P([V(.5,.44),V(.9,.5),V(.9,.78),V(.5,.78)],(.42,.42,.4))
i=sn("iron"); i.P([V(.06,.74),V(.22,.38),V(.82,.38),V(.94,.74)],(.5,.56,.64)); i.P([V(.22,.38),V(.82,.38),V(.78,.5),V(.2,.5)],(.78,.84,.9)); i.R(.06,.66,.88,.1,(.36,.4,.48))
i=sn("food"); i.E(.5,.58,.42,.28,(.82,.58,.26)); i.E(.5,.5,.38,.2,(.92,.7,.36))
for x in (.3,.5,.7): i.P([V(x-.04,.58),V(x,.4),V(x+.06,.44),V(x+.02,.6)],(.7,.44,.18))
i=sn("pop"); i.E(.5,.28,.17,.2,(.9,.74,.58)); i.P([V(.14,.9),V(.18,.62),V(.34,.5),V(.66,.5),V(.82,.62),V(.86,.9)],(.36,.56,.78))
i=sn("idle"); Y=(1,.9,.5); i.R(.08,.16,.84,.5,Y); i.E(.08,.41,.07,.25,Y); i.E(.92,.41,.07,.25,Y); i.P([V(.24,.62),V(.4,.62),V(.2,.88)],Y)
for x in (.3,.5,.7): i.E(x,.41,.06,.08,(.45,.32,.1))
i=sn("homeless"); i.R(.22,.46,.56,.42,(.7,.62,.5)); i.P([V(.1,.5),V(.5,.14),V(.9,.5)],(.62,.3,.24)); i.P([V(.62,.62),V(.72,.52),V(.96,.78),V(.86,.88)],(.95,.3,.25)); i.P([V(.86,.52),V(.96,.62),V(.72,.88),V(.62,.78)],(.95,.3,.25))

for n,i in ui.items(): open(f"{OUT}/ui/{n}.svg","w").write(i.svg(18))
for n,i in stock.items(): open(f"{OUT}/stock/{n}.svg","w").write(i.svg(22,outline=("#14120f",0.07)))
print(len(ui),len(stock))

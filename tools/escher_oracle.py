"""Independent turning distance, source correspondence, and finite patch checks."""
import argparse
from bisect import bisect_right
from cmath import exp
from fractions import Fraction
import hashlib
from itertools import combinations
import json
import math
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat

PROFILES=("periodic","split","penrose")
VIEWS=tuple(v for n in PROFILES for v in (n,n+"-baseline"))+("penrose-offset","common-a","common-b")
PAIRS={a:b for a,b in zip("abcdefgh","gedcbhaf")}


def load(folder,name):
    return json.loads((folder/name).read_text(encoding="utf-8"))


def turning(poly):
    t,theta=[0.0],[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        dx,dy=b[0]-a[0],b[1]-a[1]
        t.append(t[-1]+math.hypot(dx,dy))
        angle=math.atan2(dy,dx)
        if theta:
            angle=theta[-1]+math.remainder(angle-theta[-1],math.tau)
        theta.append(angle)
    return [v/t[-1] for v in t],theta


def distance(a,b):
    p,u=turning(a)
    q,v=turning(b)
    best=math.inf
    for delta in {(y-x)%1 for x in p[:-1] for y in q[:-1]}:
        breaks=sorted(set(p)|{(y-delta)%1 for y in q[:-1]})
        mean,second=0.0,0.0
        for a,b in zip(breaks,breaks[1:]):
            s=(a+b)/2
            t=s+delta
            cycle=math.floor(t)
            i=bisect_right(p,s)-1
            j=bisect_right(q,t-cycle)-1
            diff=u[i]-v[j]-cycle*math.tau
            mean+=(b-a)*diff
            second+=(b-a)*diff**2
        best=min(best,max(0.0,second-mean*mean))
    return math.sqrt(best)


def p3_prototypes(witness):
    d=1024
    u,v=[complex(witness[i],-witness[i+1])/d for i in (0,2)]
    def direction(k): return exp(1j*math.pi*k/10)
    def around(center,k,p): return center+(p-center)*direction(k)
    A,B=complex(math.sin(math.pi/5)),complex(0,math.cos(math.pi/5))
    D=-B
    E,F=A+u*direction(7),A+v*direction(7)
    G,H=around(B,-4,F),around(B,-4,E)
    I,J=D+v*1j,D+u*1j
    K,L,M=around(D,-4,J),around(D,-4,I),around(D,-4,H)
    thick=[A,E,F,B,G,H,I,J,D,K,L,M]
    A,B=complex(math.sin(math.pi/10)),complex(0,math.cos(math.pi/10))
    C,D=-A,-B
    E,F=A+u*direction(12),B+v*direction(14)
    G=around(C,-8,F)
    H,I=D+u*direction(6),D+u*direction(2)
    J,K=around(A,8,F),around(A,8,E)
    thin=[A,E,F,C,G,H,D,I,J,K]
    points={}
    for kind,poly,labels in (("thick",thick,"abcdefegabhg"),("thin",thin,"afcdegabhg")):
        profile=[]
        for a,b,label in zip(poly,poly[1:]+poly[:1],labels):
            profile.append(a)
            group=next(i for i,g in enumerate(("ag","be","cd","fh")) if label in g)
            q=witness[4+group]
            if q:
                profile.append((a+b)/2+1j*(b-a)*q/d*(1 if label in "abcf" else -1))
        points[kind]=profile
    return points


def paths(tiling):
    edges={e["id"]:e for e in tiling["edges"]}
    vertices={v["id"]:v for v in tiling["vertices"]}
    polys={}
    for c in tiling["cells"]:
        path=[]
        last=None
        for u in c["boundary"]:
            edge=edges[u["edge"]]
            line=list(map(tuple,edge["path"]))
            a,b=map(lambda k:tuple(vertices[edge[k]]["point"]),("from","to"))
            assert line[0]==a and line[-1]==b
            if u["reversed"]:
                line.reverse()
            assert last is None or line[0]==last
            last=line[-1]
            path.extend(line[:-1])
        assert last==path[0]
        polys[c["id"]]=path
    return edges,vertices,polys


def area(p):
    return sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(p,p[1:]+p[:1]))/2


def turn(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def clip(points,box):
    poly=list(points)
    for axis,side,bound in ((0,1,box[0]),(1,1,box[1]),(0,-1,box[2]),(1,-1,box[3])):
        if not poly:
            break
        result=[]
        for a,b in zip(poly,poly[1:]+poly[:1]):
            u,v=(a[axis]-bound)*side,(b[axis]-bound)*side
            if (u>=0)!=(v>=0):
                t=u/(u-v)
                result.append(tuple(x+(y-x)*t for x,y in zip(a,b)))
            if v>=0:
                result.append(b)
        poly=result
    return poly


def extent(poly):
    return (min(p[0] for p in poly),min(p[1] for p in poly),max(p[0] for p in poly),max(p[1] for p in poly))


def intersects(a,b):
    return a[0]<=b[2] and b[0]<=a[2] and a[1]<=b[3] and b[1]<=a[3]


def crossing(a,b,c,d):
    u,v,x,y=turn(a,b,c),turn(a,b,d),turn(c,d,a),turn(c,d,b)
    return min(abs(k) for k in (u,v,x,y))>1e-11 and u*v<0 and x*y<0


def coverage(polys,query):
    visible=[(extent(p),p) for p in polys if intersects(extent(p),query)]
    measured=sum(area(clip(p,query)) for _,p in visible)
    expected=(query[2]-query[0])*(query[3]-query[1])
    assert abs(measured-expected)<5e-9,(measured,expected)
    candidates=0
    for (a,p),(b,q) in combinations(visible,2):
        if intersects(a,b):
            candidates+=1
            assert not any(crossing(u,v,x,y) for u,v in zip(p,p[1:]+p[:1]) for x,y in zip(q,q[1:]+q[:1]))
    return {"area_residual_cm2":abs(measured-expected),"nearby_polygon_pairs":candidates}


def audit(folder,name,model):
    instance=load(folder,name+".instance")
    ext=instance["extensions"]["escher"]
    request=ext["request"]
    solver=ext["solver"]
    tiling=instance["structures"]["tiling"]
    edges,vertices,polys=paths(tiling)
    assert all(area(p)>0 for p in polys.values())
    out=coverage(polys.values(),request["query"])
    coupled=0
    for e in edges.values():
        incidence=e["incidence"]
        assert len(incidence)==(2 if e["role"]=="interior" else 1)
        assert e["owner"]==min(u["cell"] for u in incidence)
        if len(incidence)==2:
            a,b=incidence
            if request["profile"]=="penrose":
                assert PAIRS[a["label"]]==b["label"] and a["reverse"]!=b["reverse"]
            else:
                assert a["reversed"]!=b["reversed"]
            coupled+=1
    if request["profile"]=="penrose":
        raw=(folder/"penrose-source.instance").read_bytes()
        if name=="penrose":
            assert ext["scaffold"]==json.loads(raw)
            assert hashlib.sha256(raw).hexdigest()==ext["certificate"]["source_sha256"]
        source=ext["scaffold"]["structures"]["tiling"]
        base={c["id"]:c for c in source["cells"]}
        step=request["step_cm"]
        origin=complex(*request["frame"]["origin"])
        shape=p3_prototypes(model["witness"])
        for kind,actual in zip(("thick","thin"),model["optimized"]):
            assert len(actual)==len(shape[kind])
            assert max(abs(complex(*p)-q) for p,q in zip(actual,shape[kind]))<1e-12
        for cell in tiling["cells"]:
            src=base[cell["source_ref"]]
            assert cell["prototype"]==src["prototype"]
            basis=exp(1j*math.pi/10)
            anchor=sum(k*basis**(4*i) for i,k in enumerate(cell["source_anchor"]))
            proto=shape[cell["prototype"]]
            expected=[origin+step*(anchor+basis**cell["rotation"]*(p-proto[0])) for p in proto]
            assert len(expected)==len(polys[cell["id"]])
            assert max(abs(complex(*a)-b) for a,b in zip(polys[cell["id"]],expected))<1e-11
        for v in vertices.values():
            q=sum(n*exp(1j*math.pi*j/10) for j,n in enumerate(v["cyclotomic"]))/2048
            assert abs(origin+step*q-complex(*v["point"]))<1e-11
    else:
        certificate=ext["certificate"]
        assert certificate["isohedral"]=="IH41" and certificate["product"]<1
        slot=default_slots(tiling["cells"])
        want={"west","east"} if request["profile"]=="split" else {"mono"}
        assert all(set(v)==want for v in slot.values())
        step,aspect,shear=request["step_cm"],request["aspect"],request["shear"]
        origin=request["frame"]["origin"]
        for e in edges.values():
            for chart,p in zip(e["rational_chart"],e["path"]):
                x,y=(Fraction(*v) for v in chart)
                want=(origin[0]+step*(float(x)+shear*float(y)),origin[1]+step*aspect*float(y))
                assert math.dist(want,p)<1e-12
        for c in tiling["cells"]:
            index=1 if c["prototype"]=="east" else 0
            i,j=c["source_slot"]
            expected=[(origin[0]+step*(p[0]+i+shear*j),origin[1]+step*(p[1]+aspect*j))
                      for p in model["optimized"][index]]
            assert max(math.dist(a,b) for a,b in zip(expected,polys[c["id"]]))<1e-12
        assert all(abs(sum(area(polys[cid]) for cid in ids.values())-step*step*aspect)<1e-11
                   for ids in slot.values())
    baseline=[distance(p,t) for p,t in zip(model["baseline"],model["targets"])]
    optimized=[distance(p,t) for p,t in zip(model["optimized"],model["targets"])]
    assert max(abs(a-b) for a,b in zip(baseline,solver["baseline_errors"]))<1e-10
    assert max(abs(a-b) for a,b in zip(optimized,solver["errors"]))<1e-10
    assert max(optimized)<.98*max(baseline) and max(optimized)>1e-4
    out.update(coupled_edges=coupled,cells=len(polys),baseline=baseline,optimized=optimized)
    return out


def default_slots(cells):
    slots={}
    for c in cells:
        slot=slots.setdefault(tuple(c["source_slot"]),{})
        assert c["prototype"] not in slot
        slot[c["prototype"]]=c["id"]
    return slots


def raster(folder,name,existing):
    svg=folder/(name+".svg")
    view=[float(n) for n in ET.parse(svg).getroot().attrib["viewBox"].split()]
    w,h=[int(n*50+.5) for n in view[2:]]
    a,b=[folder/f"{name}-{backend}.png" for backend in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-r","127","-W",str(w),"-H",str(h),"-png","-singlefile",
                        str(folder/(name+".pdf")),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(svg),"--export-background=white","--export-background-opacity=1",
                        f"--export-width={w}",f"--export-filename={b}"],check=True)
    images=[Image.open(p).convert("RGB") for p in (a,b)]
    assert all(im.size==(w,h) for im in images),(name,(w,h),[im.size for im in images])
    mean=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
    assert mean<.055 and min(sum(im.convert("L").histogram()[:230]) for im in images)>w*h*.8
    return {"mean_backend_error":mean,"dimensions":[w,h]}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--folder",type=Path)
    parser.add_argument("--existing-rasters",action="store_true")
    args=parser.parse_args()
    folders=[args.folder] if args.folder else [p.parent for p in Path("build/escher").glob("*/receipt.json")]
    assert folders
    for folder in folders:
        receipt=load(folder,"receipt.json")
        for n,h in receipt["outputs"].items():
            assert hashlib.sha256((folder/n).read_bytes()).hexdigest()==h
        models=load(folder,"prototype-models.json")
        results={n:audit(folder,n,models[n]) for n in PROFILES}
        results["penrose-offset"]=audit(folder,"penrose-offset",models["penrose"])
        failures=load(folder,"solver-failures.json")
        assert [failures[k]["status"] for k in ("limited","inadmissible","unimproved")]==[
            "limited","inadmissible_witness","no_improvement"]
        assert failures["invalid_target"]
        renders={n:raster(folder,n,args.existing_rasters) for n in VIEWS}
        for backend in ("pdf","svg"):
            a,b=[Image.open(folder/f"common-{k}-{backend}.png").convert("RGB") for k in ("a","b")]
            assert ImageChops.difference(a,b).getbbox() is None
        report={"geometry":results,"renders":renders,"shared_edges":receipt["shared_edges"]}
        (folder/"oracle.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
        print("Escherization independent oracle:",{n:(max(v["baseline"]),max(v["optimized"]))
              for n,v in results.items()},len(renders),"render pairs")


if __name__=="__main__":
    main()

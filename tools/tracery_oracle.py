"""Independent analytic graph, band and render checks for the tracery stage."""
import argparse
from collections import defaultdict
import hashlib
from itertools import combinations
import json
import math
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat

NAMES=("prototype","rosette","narrow","rose")
VIEWS=tuple(v for n in NAMES for v in (n,n+"-diagnostic"))+("edited","join-detail","join-detail-diagnostic")
EPS=2e-10


def read(folder,name):
    return json.loads((folder/name).read_text(encoding="utf-8"))


def point(c,r,a):
    return c[0]+r*math.cos(a),c[1]+r*math.sin(a)


def close(a,b,tol=EPS):
    return math.dist(a,b)<tol


def audit_graph(x):
    graph=x["structures"]["graph"]
    ext=x["extensions"]["tracery"]
    meta=ext["grammar"]
    curves=ext["curves"]
    verts={v["id"]:v["point"] for v in graph["vertices"]}
    neighbors=defaultdict(set)
    ends=defaultdict(set)
    arc_count=0
    for edge in graph["edges"]:
        a,b=edge["from"],edge["to"]
        assert a!=b and not close(verts[a],verts[b])
        neighbors[a].add(b);neighbors[b].add(a)
        c=curves[edge["id"]]
        if c["kind"]=="arc":
            assert 0<abs(c["sweep"])<math.tau and c["radius"]>0
            assert close(verts[a],point(c["center"],c["radius"],c["start"]))
            assert close(verts[b],point(c["center"],c["radius"],c["start"]+c["sweep"]))
            ends[c["source"]].update((a,b))
            arc_count+=1
    seen={next(iter(verts))}
    queue=list(seen)
    for v in queue:
        for n in neighbors[v]-seen:
            seen.add(n);queue.append(n)
    assert seen==set(verts)
    for a in meta["arches"]:
        width=a["right"]-a["left"]
        axis=(a["left"]+a["right"])/2
        r=width*a["excess"]
        shift=r-width/2
        assert abs(r-a["radius"])<EPS and abs(shift-a["center_offset"])<EPS
        assert close(a["centers"][0],(axis+shift,a["spring"]))
        assert close(a["centers"][1],(axis-shift,a["spring"]))
        # Reconstruct the apex from the two circle equations.
        assert close(a["apex"],(axis,a["spring"]+math.sqrt((r-shift)*(r+shift))))
        for center,jamb in zip(a["centers"],(a["left"],a["right"])):
            assert abs(math.dist(center,(jamb,a["spring"]))-r)<EPS
            assert center[1]==a["spring"]  # horizontal radius, vertical jamb tangent
    residuals=[]
    for t in meta["contacts"]:
        circle=next(c for c in curves.values() if c.get("source")==t["arc"])
        p=verts[t["id"]]
        q,m=t["center"],circle["center"]
        rr,rs=t["radius"],circle["radius"]
        expected=rs-rr if t["kind"]=="internal" else rs+rr
        errors=[abs(math.dist(q,m)-expected),abs(math.dist(q,p)-rr),abs(math.dist(m,p)-rs)]
        # Collinearity of the radii at the actual shared graph vertex.
        errors.append(abs((q[0]-p[0])*(m[1]-p[1])-(q[1]-p[1])*(m[0]-p[0])))
        assert max(errors)<EPS
        assert t["id"] in ends[t["arc"]] and t["id"] in meta["rings"][0]["ports"]
        residuals.extend(errors)
    if meta["contacts"]:
        center=meta["rings"][0]["center"]
        assert abs(center[0]-meta["arches"][0]["axis"])<EPS
        p=[verts[t["id"]] for t in meta["contacts"]]
        for a,b in (p[:2],p[2:]):
            assert abs(a[0]+b[0]-2*center[0])<EPS and abs(a[1]-b[1])<EPS
    petals={}
    for f in meta["foils"]:
        c,R=f["center"],f["container_radius"]
        n,r=f["count"],f["foil_radius"]
        assert abs(r-(R-r)*math.sin(math.pi/n))<EPS
        if "parent" in f:
            parent,pr=petals[f["parent"]]
            assert close(parent["center"],c) and abs(pr-R)<EPS
            assert parent["tip"]==f["petals"][0]["tip"]
        for i,p in enumerate(f["petals"]):
            q=f["petals"][(i+1)%n]
            assert abs(math.dist(p["center"],c)-(R-r))<EPS
            assert abs(math.dist(p["center"],q["center"])-2*r)<EPS
            assert p["to"]==q["from"] and abs(math.dist(verts[p["tip"]],c)-R)<EPS
            for v in (p["from"],p["to"],p["tip"]):
                assert v in ends[p["id"]] and abs(math.dist(verts[v],p["center"])-r)<EPS
            petals[p["id"]]=(p,r)
    return {"vertices":len(verts),"edges":len(graph["edges"]),"arcs":arc_count,
            "contacts":len(meta["contacts"]),"contact_max_residual":max(residuals,default=0),
            "foil_rings":len(meta["foils"])}


def sample(cmds):
    paths=[]
    for c in cmds:
        if c[0]=="M":
            path=[tuple(c[1:])];paths.append(path)
        elif c[0]=="L":
            path.append(tuple(c[1:]))
        elif c[0]=="C":
            a=path[-1]
            b,c1,d=c[1:3],c[3:5],c[5:7]
            for i in range(1,9):
                t=i/8;u=1-t
                path.append(tuple(u**3*p+3*u*u*t*q+3*u*t*t*r+t**3*s for p,q,r,s in zip(a,b,c1,d)))
        else:
            assert c[0]=="Z"
    return paths


def signed_area(p):
    return sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(p,p[1:]+p[:1]))/2


def turn(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def proper_cross(a,b,c,d):
    return turn(a,b,c)*turn(a,b,d)<-1e-18 and turn(c,d,a)*turn(c,d,b)<-1e-18


def bands(folder,name,x):
    meta=x["extensions"]["tracery"]["grammar"]
    curves=x["extensions"]["tracery"]["curves"]
    edge_paths={o["semantic_ref"]:o["commands"] for o in read(folder,name+"-diagnostic.scene")["operations"]}
    errors=[]
    for edge,c in curves.items():
        if c["kind"]=="arc":
            for p in sample(edge_paths[edge])[0]:
                errors.append(abs(math.dist(p,c["center"])-c["radius"])/c["radius"])
    assert max(errors)<5e-6
    profiles=[o for o in read(folder,name+".scene")["operations"] if o["paint"].get("fill_rule")=="evenodd"]
    assert len(profiles)==len(meta["arches"])+len(meta["rings"])
    half=.115/2
    for index,o in enumerate(profiles):
        paths=sample(o["commands"])
        assert len(paths)==2
        outer,inner=paths
        assert abs(signed_area(outer))>abs(signed_area(inner))>EPS
        sides=[list(zip(p,p[1:]+p[:1])) for p in paths]
        for group in sides:
            assert not any(proper_cross(*a,*b) for a,b in combinations(group,2))
        assert not any(proper_cross(*a,*b) for a in sides[0] for b in sides[1])
        if index<len(meta["arches"]):
            a=meta["arches"][index]
            for path,offset in ((outer,-half),(inner,half)):
                r=a["radius"]-offset
                y=a["spring"]+math.sqrt(r*r-a["center_offset"]**2)
                apex=max(path,key=lambda p:p[1])
                assert close(apex,(a["axis"],y))
                assert close(path[0],(a["left"]+offset,a["base"]+offset))
        else:
            ring=meta["rings"][index-len(meta["arches"])]
            for path,offset in ((outer,half),(inner,-half)):
                r=ring["radius"]+offset
                assert max(abs(math.dist(p,ring["center"])-r) for p in path)<5e-6*r
    return {"noncrossing_bands":len(profiles),"max_cubic_relative_radial_error":max(errors)}


def raster(folder,name,existing):
    svg=folder/(name+".svg")
    view=[float(v) for v in ET.parse(svg).getroot().attrib["viewBox"].split()]
    rate=100 if name.startswith("join-detail") else 50
    w,h=(int(v*rate+.5) for v in view[2:])
    a,b=[folder/f"{name}-{engine}.png" for engine in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-r",str(rate*2.54),"-W",str(w),"-H",str(h),"-png","-singlefile",
                        str(folder/(name+".pdf")),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(svg),"--export-background=white","--export-background-opacity=1",
                        f"--export-width={w}",f"--export-filename={b}"],check=True)
    imgs=[Image.open(p).convert("RGB") for p in (a,b)]
    assert all(im.size==(w,h) for im in imgs),(name,(w,h),[im.size for im in imgs])
    mean=sum(ImageStat.Stat(ImageChops.difference(*imgs)).mean)/(3*255)
    assert mean<.045 and min(sum(im.convert("L").histogram()[:220]) for im in imgs)>100
    detail={"mean_backend_error":mean,"size":[w,h]}
    if name=="prototype":
        y=int(h-1.3*rate)
        weights=[sum(im.convert("L").getpixel((x,y))<220 for x in range(3,28)) for im in imgs]
        assert all(5<=n<=7 for n in weights),(name,weights)
        detail["left_jamb_pixels_at_127dpi"]=weights
    if name=="join-detail-diagnostic":
        probes=[sum(r>135 and r-g>45 and g<120 for r,g,b in
                    im.crop((w//2-5,h//2-5,w//2+5,h//2+5)).getdata()) for im in imgs]
        assert min(probes)>25,(name,probes)
        detail["centered_tangent_marker_pixels"]=probes
    return detail


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--folder",type=Path)
    parser.add_argument("--existing-rasters",action="store_true")
    args=parser.parse_args()
    folders=[args.folder] if args.folder else [p.parent for p in Path("build/tracery").glob("*/receipt.json")]
    assert folders
    for folder in folders:
        receipt=read(folder,"receipt.json")
        for n,h in receipt["outputs"].items():
            assert hashlib.sha256((folder/n).read_bytes()).hexdigest()==h
        out={}
        for n in NAMES:
            x=read(folder,n+".instance")
            out[n]=audit_graph(x)
            out[n].update(bands(folder,n,x))
        edited=read(folder,"edited.instance")
        out["edited"]=audit_graph(edited)
        assert out["rose"]["foil_rings"]==7 and out["rosette"]["contacts"]==out["narrow"]["contacts"]==4
        result={"geometry":out,"renders":{n:raster(folder,n,args.existing_rasters) for n in VIEWS}}
        (folder/"oracle.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
        print("Gothic independent oracle:",sum(x["arcs"] for x in out.values()),"analytic arcs,",
              sum(x["contacts"] for x in out.values()),"tangent contacts,",len(VIEWS),"render pairs")


if __name__=="__main__":
    main()

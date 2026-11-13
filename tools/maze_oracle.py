"""Independently reconstruct maze openings, solve the export, and audit the source chart."""
import argparse
import hashlib
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ET
from collections import Counter, deque
from pathlib import Path
from statistics import mean

from PIL import Image, ImageChops, ImageStat

CASES=("directional","unguided","ribbon","perspective","spiral","vortex","random","guided","holed","aperiodic")
SOLUTIONS=("directional","guided","holed","aperiodic")
VIEWS=CASES+tuple(k+"-solution" for k in SOLUTIONS)+("crop",)
NS="{http://www.w3.org/2000/svg}"
NUMBERS=re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
EPS=2e-9


def edge(a,b):
    return tuple(sorted((a,b)))


def parse_paths(folder,name):
    root=ET.parse(folder/f"{name}.svg").getroot()
    assert not list(root.iter(NS+"image"))
    assert not re.search(rb"/Subtype\s*/Image\b",(folder/f"{name}.pdf").read_bytes())
    paths=[p for p in root.iter(NS+"path") if p.get("stroke")]
    result=[]
    for path in paths:
        values=list(map(float,NUMBERS.findall(path.attrib["d"])))
        assert len(values)%2==0
        points=[tuple(values[i:i+2]) for i in range(0,len(values),2)]
        result.append((points,float(path.attrib["stroke-width"])))
    return result


def shortest(adjacency,start,end):
    frontier=deque([start])
    prev={start:None}
    while frontier:
        p=frontier.popleft()
        for next_cell in adjacency[p]:
            if next_cell not in prev:
                prev[next_cell]=p
                frontier.append(next_cell)
    assert len(prev)==len(adjacency)
    route=[]
    while end is not None:
        route.append(end)
        end=prev[end]
    return route[::-1]


def wall_tone(g,q):
    w,p,s=q["min_wall"],q["min_passage"],q["max_spacing"]
    level=(1-g)*p/s+g*(1-w/s)
    spacing=max(p/level,w/(1-level))
    return spacing,spacing*(1-level)


def same_point(a,b):
    return math.dist(a,b)<EPS


def distance_to_line(p,a,b):
    point,left,right=(complex(*v) for v in (p,a,b))
    v=right-left
    t=max(0,min(1,((point-left)/v).real))
    return abs(point-left-t*v)


def side(a,b,p):
    return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])


def seg_gap(a,b,p,q):
    if side(a,b,p)*side(a,b,q)<0 and side(p,q,a)*side(p,q,b)<0:
        return 0
    return min(distance_to_line(a,p,q),distance_to_line(b,p,q),
               distance_to_line(p,a,b),distance_to_line(q,a,b))


def audit(folder,name):
    x=json.loads((folder/f"{name}.instance").read_text())
    e=x["extensions"]["maze"]
    q=e["request"]
    points=e["points"]
    cells={c["id"]:c for c in e["cells"]}
    wall_index={w["id"]:w for w in e["walls"]}
    s=e["solution"]
    chart=e["chart"]
    incidences={}
    for id,c in cells.items():
        ids=c["vertices"]
        for a,b in zip(ids,ids[1:]+ids[:1]):
            incidences.setdefault(edge(a,b),[]).append(id)
            assert side(points[a]["point"],points[b]["point"],c["center"])>0
    assert len(incidences)==len(wall_index)
    candidates={}
    closed={}
    terminal={}
    for wall in e["walls"]:
        a,b=[points[wall[k]]["point"] for k in ("from","to")]
        pair=edge(wall["from"],wall["to"])
        assert sorted(incidences[pair])==sorted(wall["cells"])
        assert len(wall["cells"]) in (1,2)
        want_s,want_w=wall_tone(wall["light"],q)
        assert abs(want_s-wall["target_spacing"])<EPS
        assert abs(want_w-wall["target_width"])<EPS
        assert q["min_wall"]-EPS<=wall["width"]<=want_w+EPS
        assert math.dist(a,b)>=q["min_passage"]+q["min_wall"]-EPS
        assert all(2*distance_to_line(cells[c]["center"],a,b)-wall["width"]>=q["min_passage"]-EPS
                   for c in wall["cells"])
        if len(wall["cells"])==2:
            candidates[pair]=wall
        if not wall["open"]:
            closed[pair]=wall
        elif len(wall["cells"])==1:
            terminal[wall["terminal"]]=wall
    assert set(terminal)=={"entry","exit"}
    assert terminal["entry"]["id"]==s["entry"] and terminal["exit"]["id"]==s["exit"]
    geometry_index={edge(tuple(points[a]["point"]),tuple(points[b]["point"])):edge(a,b) for a,b in incidences}
    assert len(geometry_index)==len(incidences)
    # Match physical SVG line coordinates to primal incidences without using passage flags.
    rendered={}
    for vertices,width in parse_paths(folder,name):
        assert len(vertices)==2
        pair=geometry_index.get(edge(*vertices))
        if pair is None:
            left,right=vertices
            close=[pair for (a,b),pair in geometry_index.items()
                   if (same_point(a,left) and same_point(b,right)) or (same_point(a,right) and same_point(b,left))]
            assert len(close)==1,(name,vertices,len(close))
            pair=close[0]
        assert pair not in rendered
        rendered[pair]=width
    assert rendered.keys()==closed.keys()
    assert all(abs(rendered[k]-closed[k]["width"])<EPS for k in closed)
    adjacency={k:[] for k in cells}
    passages=0
    for pair,w in candidates.items():
        if pair not in rendered:
            a,b=w["cells"]
            adjacency[a].append(b)
            adjacency[b].append(a)
            passages+=1
    assert passages==len(cells)-1
    independent=shortest(adjacency,terminal["entry"]["cells"][0],terminal["exit"]["cells"][0])
    assert independent==s["route"]
    # Independent constrained-MST certificate. For each unselected edge, replacing
    # an unpinned edge on its fundamental cycle cannot lower the tree weight.
    pinned=set(s["guide"])
    tree_walls={edge(*w["cells"]):w for w in candidates.values() if w["open"]}
    for wall in candidates.values():
        if not wall["open"]:
            a,b=wall["cells"]
            path=shortest(adjacency,a,b)
            weight=round(wall["weight"]*1e12)
            for u,v in zip(path,path[1:]):
                w=tree_walls[edge(u,v)]
                assert w["id"] in pinned or round(w["weight"]*1e12)<=weight
    route_edges={edge(a,b) for a,b in zip(independent,independent[1:])}
    assert len(route_edges)==len(s["crossings"])
    assert all(edge(*wall_index[k]["cells"]) in route_edges and wall_index[k]["open"] for k in s["crossings"])
    assert set(s["guide"])<=set(s["crossings"])
    ink_clearance=None
    if name in SOLUTIONS:
        sol=parse_paths(folder,name+"-solution")
        plain=parse_paths(folder,name)
        assert sol[:-1]==plain
        path,width=sol[-1]
        expect=[terminal["entry"]["mid"]]
        for i,k in enumerate(independent):
            expect.append(cells[k]["center"])
            if i<len(s["crossings"]):
                expect.append(wall_index[s["crossings"][i]]["mid"])
        expect.append(terminal["exit"]["mid"])
        assert len(path)==len(expect) and all(same_point(a,b) for a,b in zip(path,expect))
        clearance=math.inf
        for a,b in zip(path,path[1:]):
            for w in closed.values():
                c,d=[points[w[k]]["point"] for k in ("from","to")]
                clearance=min(clearance,seg_gap(a,b,c,d)-(w["width"]+width)/2)
        assert clearance>(q["min_passage"]-width)/2-1e-9,(name,clearance)
        ink_clearance=clearance
    if name=="perspective":
        k=q["perspective"]
        l,b,r,t=q["bounds"]
        for v in points.values():
            u,y=v["uv"]
            z=1+k*y
            expected=(l+(r-l)*(.5+(u-.5)/z),b+(t-b)*(1+k)*y/z)
            assert same_point(v["point"],expected)
        lower=max(v["point"][0] for v in points.values() if v["uv"][1]==0)-min(v["point"][0] for v in points.values() if v["uv"][1]==0)
        upper=max(v["point"][0] for v in points.values() if v["uv"][1]==1)-min(v["point"][0] for v in points.values() if v["uv"][1]==1)
        assert abs(lower/upper-1-k)<EPS
    if name=="holed":
        assert chart["removed"] and all(cell not in cells for cell in chart["removed"])
    if name=="aperiodic":
        assert all(c["source_ref"]==c["id"] and len(c["vertices"])==4 for c in cells.values())
        assert chart["source_cells"]>len(cells)
    counts=Counter(w.get("bias","boundary") for w in e["walls"] if w["open"])
    return {"cells":len(cells),"passages":passages,"closed_walls":len(closed),"route_cells":len(independent),
            "guide_edges":len(s["guide"]),"preferred_removals":counts["preferred-removal"],
            "limited_wall_widths":sum(w["width_limited"] for w in e["walls"]),"ink_clearance_cm":ink_clearance}


def raster(folder,name,existing):
    box=ET.parse(folder/f"{name}.svg").getroot().attrib["viewBox"].split()
    w,h=[math.floor(float(n)*64+.5) for n in box[2:]]
    a,b=[folder/f"{name}-{backend}.png" for backend in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-scale-to-x",str(w),"-scale-to-y",str(h),"-png","-singlefile",
                        str(folder/f"{name}.pdf"),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(folder/f"{name}.svg"),"--export-background=white",
                        "--export-background-opacity=1",f"--export-width={w}",f"--export-height={h}",
                        f"--export-filename={b}"],check=True)
    pdf,svg=[Image.open(p).convert("RGB") for p in (a,b)]
    assert pdf.size==svg.size==(w,h),(name,pdf.size,svg.size,(w,h))
    error=sum(ImageStat.Stat(ImageChops.difference(pdf,svg)).mean)/(3*255)
    assert error<.05,(name,error)
    dark=sum(pdf.convert("L").histogram()[:190])/(w*h)
    assert .01<dark<.65,(name,dark)
    out={"mean_backend_error":error,"dark_fraction":dark,"dimensions":[w,h]}
    if name=="directional":
        gray=pdf.convert("L")
        samples=[]
        for left,right in ((.13,.34),(.41,.59),(.66,.87)):
            crop=gray.crop((round(left*w),round(.16*h),round(right*w),round(.84*h)))
            samples.append(1-ImageStat.Stat(crop).mean[0]/255)
        assert samples[0]>samples[1]>samples[2],samples
        out["tone_darkness_bands"]=samples
    if name=="ribbon":
        gray=pdf.convert("L")
        inside,outside=[],[]
        for y in range(h):
            v=(7.28-(y+.5)*7.56/h)/7
            for x in range(w):
                u=(-.28+(x+.5)*10.56/w)/10
                if .05<u<.95 and .08<v<.92:
                    d=abs(v-(.5+.19*math.sin(2*math.pi*u)))
                    tone=1-gray.getpixel((x,y))/255
                    if d<.12:
                        inside.append(tone)
                    elif d>.24:
                        outside.append(tone)
        out["ribbon_darkness"]=[mean(inside),mean(outside)]
        assert mean(inside)>2*mean(outside)
    return out


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--folder",type=Path)
    p.add_argument("--existing-rasters",action="store_true")
    args=p.parse_args()
    folders=[args.folder] if args.folder else [x.parent for x in Path("build/maze").glob("*/receipt.json")]
    assert folders
    for folder in folders:
        r=json.loads((folder/"receipt.json").read_text())
        for name,sha in r["outputs"].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==sha
        audits={name:audit(folder,name) for name in CASES}
        assert audits["directional"]["preferred_removals"]>audits["unguided"]["preferred_removals"]+35
        assert audits["guided"]["guide_edges"]>=20
        assert audits["vortex"]["route_cells"]!=audits["spiral"]["route_cells"]
        renders={name:raster(folder,name,args.existing_rasters) for name in VIEWS}
        report={"geometry":audits,"renders":renders}
        (folder/"oracle.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf8")
        print("Maze oracle passed:",len(audits),"exported graphs,",len(renders),"render pairs",
              "and",sum(x["cells"] for x in audits.values()),"cells",flush=True)


if __name__=="__main__":
    main()


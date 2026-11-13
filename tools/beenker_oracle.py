"""Independent Decimal reconstruction, coverage and render checks for Stage 17."""
import argparse
from collections import defaultdict
from decimal import Decimal as D, ROUND_CEILING, getcontext
import hashlib
from itertools import combinations
import json
import math
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat

getcontext().prec = 76
ROOT2 = D(2).sqrt()
H = ROOT2/2
DIR = ((D(1),D(0)), (H,H), (D(0),D(1)), (-H,H))
STAR = ((D(1),D(0)), (-H,H), (D(0),D(-1)), (H,H))
SMALL = D("1e-58")
FUZZ = D("1e-10")
NAMES = ("offset","noncentral","extended","centered","zero-plus","zero-minus","spread")
VIEWS = (*NAMES[:-1], "common-a","common-b","spread-1","spread-2")


def det(a,b):
    return a[0]*b[1]-a[1]*b[0]


def sub(a,b):
    return a[0]-b[0],a[1]-b[1]


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def read(folder,name):
    return json.loads((folder/name).read_text(encoding="utf-8"),parse_float=D)


def projected(lift, center, basis):
    shifted = [a-b for a,b in zip(lift,center)]
    return tuple(sum(k*u[i] for k,u in zip(shifted,basis)) for i in range(2))


def box(points):
    return tuple(min(p[i] for p in points) for i in range(2))+tuple(max(p[i] for p in points) for i in range(2))


def hits(a,b):
    return all(a[i]<=b[i+2]+FUZZ and b[i]<=a[i+2]+FUZZ for i in range(2))


def expand(b,pad):
    return tuple(v + (-pad if i<2 else pad) for i,v in enumerate(b))


def coordinates(i,j,m,n,gamma):
    u,v=DIR[i],DIR[j]
    a,b=D(m)-gamma[i],D(n)-gamma[j]
    cross=det(u,v)
    return (a*v[1]-b*u[1])/cross,(u[0]*b-v[0]*a)/cross


def tile(i,j,m,n,gamma,direction):
    base=coordinates(i,j,m,n,gamma)
    eps=D("1e-30")
    altered=[g+eps*s for g,s in zip(gamma,direction)]
    approached=coordinates(i,j,m,n,altered)
    k=[None]*4
    k[i],k[j]=m,n
    ties=[]
    for q in range(4):
        if q in (i,j):
            continue
        value=dot(base,DIR[q])+gamma[q]
        altered_value=dot(approached,DIR[q])+altered[q]
        k[q]=int(altered_value.to_integral_value(rounding=ROUND_CEILING))
        integer=round(value)
        if abs(value-integer)<SMALL:
            assert any(direction)
            side=1 if altered_value>integer else -1
            assert abs(altered_value-integer)>SMALL
            ties.append((q+1,integer,side))
        else:
            assert abs(value-integer)>D("1e-20"), "insufficient separation from finite probe"
            assert k[q]==int(value.to_integral_value(rounding=ROUND_CEILING))
    lifts=tuple(tuple(v+(p==i and a)+(p==j and b) for p,v in enumerate(k))
                for a,b in ((0,0),(1,0),(1,1),(0,1)))
    return lifts,ties


def clipped(poly, boundary):
    for a,b in zip(boundary,boundary[1:]+boundary[:1]):
        if not poly:
            return []
        out=[]
        for p,q in zip(poly,poly[1:]+poly[:1]):
            h=det(sub(b,a),sub(p,a))
            k=det(sub(b,a),sub(q,a))
            inside=h>=-SMALL
            if inside!=(k>=-SMALL):
                t=h/(h-k)
                out.append(tuple(x+t*(y-x) for x,y in zip(p,q)))
            if k>=-SMALL:
                out.append(q)
        poly=out
    return poly


def area(poly):
    return abs(sum(det(a,b) for a,b in zip(poly,poly[1:]+poly[:1])))/2


def audit(folder,name):
    x=read(folder,name+".instance")
    tiling=x["structures"]["tiling"]
    ext=x["extensions"]["beenker"]
    record=ext["certificate"]
    request=ext["request"]
    origin=request["frame"]["origin"]
    step=request["step_cm"]
    q=[(v-origin[i%2])/step for i,v in enumerate(request["world_query"])]
    phase=record["phase"]
    d=phase["denominator"]
    gamma=[D(n)/d for n in phase["numerators"]]
    direction=phase.get("direction",[0]*4)
    center=phase["center"]
    limits=math.ceil(max(map(abs,q)))+13
    selected,owners={},defaultdict(set)
    for i,j in combinations(range(4),2):
        for m in range(-limits,limits+1):
            for n in range(-limits,limits+1):
                lifts,ties=tile(i,j,m,n,gamma,direction)
                points=[projected(k,center,DIR) for k in lifts]
                if not hits(box(points),expand(q,4)):
                    continue
                address=(i+1,j+1,m,n)
                for a,b in zip(lifts,lifts[1:]+lifts[:1]):
                    owners[tuple(sorted((a,b)))].add(address)
                if hits(box(points),expand(q,2)):
                    selected[address]=(lifts,points,ties)
    assert len(selected)==len(tiling["cells"])
    vertices={v["id"]:v for v in tiling["vertices"]}
    edges={e["id"]:e for e in tiling["edges"]}
    all_cells={c["id"]:tuple(c["address"]) for c in tiling["cells"]}
    id_prefix=x["id"].split("/query/")[0]+"/cell/"
    for v in vertices.values():
        for label,basis in (("physical",DIR),("internal",STAR)):
            exact=[(D(a)+D(b)*ROOT2)/2 for a,b in v[label]]
            assert all(abs(a-b)<SMALL for a,b in zip(exact,projected(v["lift"],center,basis)))
        world=[o+step*p for o,p in zip(origin,projected(v["lift"],center,DIR))]
        assert max(abs(a-b) for a,b in zip(v["point"],world))<D("1e-12")
    for e in edges.values():
        a,b=(tuple(vertices[e[k]]["lift"]) for k in ("from","to"))
        assert sum(abs(p-q) for p,q in zip(a,b))==1
        expected={id_prefix+"/".join(map(str,address)) for address in owners[tuple(sorted((a,b)))]}
        assert set(e["global_cells"])==expected and len(expected)==2
        assert e["global_owner"]==min(expected)
        visible=expected & all_cells.keys()
        assert e["owner"]==min(visible)
        assert e["role"]==("interior" if len(visible)==2 else "patch_boundary")
    total_ties=0
    cut_patches=[]
    query_poly=[(q[0],q[1]),(q[2],q[1]),(q[2],q[3]),(q[0],q[3])]
    for cell in tiling["cells"]:
        address=tuple(cell["address"])
        lifts,points,ties=selected[address]
        assert list(lifts[0])==cell["base_lift"]
        assert [(t["family"],t["line"],t["side"]) for t in cell["ties"]]==ties
        total_ties+=len(ties)
        for use,k in zip(cell["boundary"],lifts):
            edge=edges[use["edge"]]
            assert tuple(vertices[edge["to"] if use["reversed"] else edge["from"]]["lift"])==k
        sides=[sub(b,a) for a,b in zip(points,points[1:]+points[:1])]
        assert all(abs(dot(side,side)-1)<SMALL for side in sides)
        square=address[1]-address[0]==2
        assert cell["prototype"]==("square" if square else "rhombus")
        assert abs(area(points)-(1 if square else H))<SMALL
        patch=clipped(points,query_poly)
        if area(patch)>SMALL:
            cut_patches.append((patch,box(patch)))
    covered=sum(area(p) for p,_ in cut_patches)
    residual=abs(covered-(q[2]-q[0])*(q[3]-q[1]))
    assert residual<SMALL,(name,residual)
    candidate_pairs=0
    for (p,a),(r,b) in combinations(cut_patches,2):
        if hits(a,b):
            assert area(clipped(p,r))<SMALL,(name,a,b)
            candidate_pairs+=1
    assert total_ties==record["ties"]["count"]
    if name.startswith("zero"):
        assert len([a for a,(_,_,t) in selected.items() if a[2:]==(0,0) and len(t)==2])==6
    symmetry=0
    if name=="centered":
        disk={frozenset(lifts) for lifts,points,_ in selected.values() if all(dot(p,p)<D("4.5")**2 for p in points)}
        for lifts in disk:
            assert frozenset((2-k[3],k[0],k[1],k[2]) for k in lifts) in disk
        symmetry=len(disk)
        assert symmetry>=40 and symmetry%8==0
    return {"cells":len(selected),"visible_cells":len(cut_patches),"area_residual":str(residual),
            "candidate_overlap_pairs":candidate_pairs,"ties":total_ties,"eightfold_disk_tiles":symmetry}


def raster(folder,name,existing):
    spread=name.startswith("spread-")
    page=name[-1] if spread else "1"
    pdf=folder/("spread.pdf" if spread else name+".pdf")
    svg=folder/(name+".svg")
    view=[float(n) for n in ET.parse(svg).getroot().attrib["viewBox"].split()]
    w,h=round(view[2]*50),round(view[3]*50)
    a,b=[folder/f"{name}-{backend}.png" for backend in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-r","127","-f",page,"-l",page,"-W",str(w),"-H",str(h),"-png",
                        "-singlefile",str(pdf),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(svg),"--export-background=white","--export-background-opacity=1",
                        f"--export-width={w}",f"--export-filename={b}"],check=True)
    images=[Image.open(p).convert("RGB") for p in (a,b)]
    assert all(im.size==(w,h) for im in images)
    error=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
    assert error<.045 and all(sum(im.convert("L").histogram()[:220])>w*h*.8 for im in images),(name,error)
    return {"mean_backend_error":error,"dimensions":[w,h]}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--folder",type=Path)
    parser.add_argument("--existing-rasters",action="store_true")
    args=parser.parse_args()
    paths=[args.folder] if args.folder else [p.parent for p in Path("build/beenker").glob("*/receipt.json")]
    assert paths,"run beenkercheck first"
    assert all(abs(sum(a[i]*b[j] for a,b in zip(DIR,STAR)))<SMALL for i in range(2) for j in range(2))
    for folder in paths:
        receipt=read(folder,"receipt.json")
        for name,digest in receipt["outputs"].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,name
        geometry={name:audit(folder,name) for name in NAMES}
        renders={name:raster(folder,name,args.existing_rasters) for name in VIEWS}
        info=subprocess.check_output(["pdfinfo",str(folder/"spread.pdf")],text=True)
        assert any(line.startswith("Pages:") and line.split()[-1]=="2" for line in info.splitlines())
        for backend in ("pdf","svg"):
            a,b=[Image.open(folder/f"common-{k}-{backend}.png").convert("RGB") for k in ("a","b")]
            assert ImageChops.difference(a,b).getbbox() is None
        report={"geometry":geometry,"render":renders,"shared":receipt["shared"]}
        (folder/"oracle.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
        print("Ammann-Beenker independent oracle:",sum(g["cells"] for g in geometry.values()),"tiles,",
              geometry["centered"]["eightfold_disk_tiles"],"eightfold disk tiles,",len(renders),"render pairs")


if __name__=="__main__":
    main()

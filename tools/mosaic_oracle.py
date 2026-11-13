"""Independent quadrature, polygon clipping and vector audit for the mosaic stage."""
import argparse
import hashlib
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ET
from itertools import combinations
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

NAMES = ("analytic", "baseline", "curved", "irregular")
TOLERANCE = 1e-9


def cross(a, b):
    return (a.conjugate()*b).imag


def side(a, b, p):
    return cross(b-a, p-a)


def clip(subject, boundary):
    for a, b in zip(boundary, boundary[1:]+boundary[:1]):
        result = []
        for p, q in zip(subject, subject[1:]+subject[:1]):
            x, y = side(a, b, p), side(a, b, q)
            if (x < 0) != (y < 0):
                result.append(p+(q-p)*x/(x-y))
            if y >= 0:
                result.append(q)
        subject = result
    return subject


def area(ring):
    return sum(cross(a,b) for a,b in zip(ring,ring[1:]+ring[:1]))/2


def nearest(feature_segments, point):
    best,axis = math.inf,1+0j
    for a,b in feature_segments:
        diff = b-a
        t = max(0,min(1,((point-a)/diff).real))
        squared = abs(point-(a+t*diff))**2
        if squared<best-1e-12:
            best,axis = squared,diff/abs(diff)
    return math.sqrt(best),axis


def audit_iterations(q, solver, end, panel, segments):
    l,b,r,t = q["bounds"]
    nx,ny = math.ceil((r-l)/q["sample"]),math.ceil((t-b)/q["sample"])
    grid = [complex(l+(i+.5)*(r-l)/nx,b+(j+.5)*(t-b)/ny) for j in range(ny) for i in range(nx)]
    grid = [(p,nearest(segments,p)[0]) for p in grid
            if all(side(a,b,p)>=-1e-12 for a,b in zip(panel,panel[1:]+panel[:1]))]
    centers = [complex(*p) for p in solver["initial"]]
    assert len(centers)==len(set(centers))==q["count"]
    for i,record in enumerate(solver["history"]+[None]):
        oriented = []
        for p in centers:
            d,axis = nearest(segments,p)
            weight = max(0,1-d/q["influence"]) if q["guided"] else 0
            aspect = math.sqrt(1+(q["aspect"]-1)*weight)
            size = q["size"]*(1-q["size_variation"]*weight)
            oriented.append((p,axis if q["guided"] else 1,2/(size*aspect),2*aspect/size))
        members = [[] for _ in centers]
        distances = []
        for p,d in grid:
            if record and record["phase"]=="feature-exclusion" and d<q["exclusion"]:
                continue
            best = math.inf
            winner = 0
            for j,(c,axis,u,v) in enumerate(oriented):
                local = (p-c)*axis.conjugate()
                value = abs(local.real)*u+abs(local.imag)*v
                if value < best-1e-12:
                    best,winner = value,j
            members[winner].append(p)
            distances.append(best)
        energy = math.fsum(distances)/len(distances) if distances else 0
        if record is None:
            assert len(distances)==solver["samples"]
            assert abs(energy-solver["final_energy"])<TOLERANCE
        else:
            assert len(distances)==record["samples"] and abs(energy-record["energy"])<TOLERANCE,(i,len(distances),record["samples"],energy,record["energy"])
            moved = []
            for c,group in zip(centers,members):
                value = sum(group)/len(group) if group else c
                moved.append(complex(*(math.floor(v*1e10+.5)/1e10 for v in (value.real,value.imag))))
            assert sum(not group for group in members)==record["empty_regions"]
            assert abs(max(abs(a-b) for a,b in zip(centers,moved))-record["max_motion"])<TOLERANCE
            centers = moved
    assert max(abs(a-complex(*b)) for a,b in zip(centers,end))<TOLERANCE
    return len(grid)


def image_color(image, point):
    color = image["background"]
    for layer in image["layers"]:
        u,v = [(p-c)/s for p,c,s in zip(point,layer["center"],layer["extent"])]
        mask = (u*u+v*v<=1 if layer["shape"]=="ellipse"
                else abs(u)<=1 and abs(v-layer["curve"]*u*u)<=1)
        if mask:
            color = layer["color"]
    return color


def crosses_interior(a,b,ring):
    lo,hi=0.0,1.0
    for p,q in zip(ring,ring[1:]+ring[:1]):
        start,end=side(p,q,a),side(p,q,b)
        if min(start,end)>TOLERANCE:
            continue
        if max(start,end)<=TOLERANCE:
            return False
        cut=(TOLERANCE-start)/(end-start)
        if end>start:
            lo=max(lo,cut)
        else:
            hi=min(hi,cut)
        if hi<=lo:
            return False
    return True


def audit(folder,name):
    ext=json.loads((folder/f"{name}.instance").read_text())["extensions"]["mosaic"]
    q=ext["request"]
    panel=[complex(*p) for p in q["panel"]]
    segments=[(complex(*a),complex(*b)) for line in q["features"] for a,b in zip(line,line[1:])]
    packing=ext["packing"]
    tiles=packing["tiles"]
    polygons=[[complex(*p) for p in t["corners"]] for t in tiles]
    angles,crossings,colors=[],0,set()
    for tile,poly in zip(tiles,polygons):
        d,axis=nearest(segments,complex(*tile["center"]))
        direction=poly[1]-poly[0]
        angle=math.atan2((direction/axis).imag,(direction/axis).real)
        if d<q["influence"]:
            angles.append(abs(math.remainder(angle,math.pi/2)))
        assert all(side(a,b,p)>-TOLERANCE for a,b in zip(panel,panel[1:]+panel[:1]) for p in poly)
        assert abs(sum(poly)/4-complex(*tile["center"]))<TOLERANCE
        assert tile["color"]==image_color(q["image"],tile["center"])
        colors.add(tuple(tile["color"]))
        if any(crosses_interior(a,b,poly) for a,b in segments):
            crossings+=1
    overlap=max((abs(area(clip(a,b))) for a,b in combinations(polygons,2)),default=0)
    assert overlap<TOLERANCE
    coverage=sum(area(p) for p in polygons)/area(panel)
    assert abs(coverage-packing["coverage"])<TOLERANCE
    assert .35<coverage<.9 and len(colors)>=3
    svg=ET.parse(folder/f"{name}.svg").getroot()
    ns="{http://www.w3.org/2000/svg}"
    assert not list(svg.iter(ns+"image"))
    assert not re.search(rb"/Subtype\s*/Image\b",(folder/f"{name}.pdf").read_bytes())
    vector_paths=[p for p in svg.iter(ns+"path") if p.attrib.get("fill","none")!="none"]
    assert len(vector_paths)==len(tiles)+1
    for path,poly in zip(vector_paths[1:],polygons):
        coords=list(map(float,re.findall(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?",path.attrib["d"])))
        assert len(coords)==8
        assert max(abs(complex(*coords[i:i+2])-p) for i,p in zip(range(0,8,2),poly))<1e-8
    grid=audit_iterations(q,ext["solver"],ext["centers"],panel,segments)
    return {"tiles":len(tiles),"coverage":coverage,"grout_fraction":1-coverage,"crossings":crossings,
            "orientation_error_rad":sum(angles)/len(angles) if angles else 0,
            "max_overlap_cm2":overlap,"colors":len(colors),"grid_samples":grid,
            "energy":ext["solver"]["final_energy"],"iterations":len(ext["solver"]["history"])}


def raster(folder,name,existing):
    view=ET.parse(folder/f"{name}.svg").getroot().attrib["viewBox"].split()
    w,h=[math.floor(float(n)*64+.5) for n in view[2:]]
    a,b=[folder/f"{name}-{backend}.png" for backend in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-scale-to-x",str(w),"-scale-to-y",str(h),"-png","-singlefile",
                        str(folder/f"{name}.pdf"),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(folder/f"{name}.svg"),"--export-background=white","--export-background-opacity=1",
                        f"--export-width={w}",f"--export-height={h}",f"--export-filename={b}"],check=True)
    images=[Image.open(p).convert("RGB") for p in (a,b)]
    assert all(im.size==(w,h) for im in images)
    mean=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
    assert mean<.035 and all(sum(n>=w*h*.005 for n,_ in im.getcolors(w*h))>=4 for im in images),(name,mean)
    return {"mean_backend_error":mean,"dimensions":[w,h]}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--folder",type=Path)
    parser.add_argument("--existing-rasters",action="store_true")
    args=parser.parse_args()
    folders=[args.folder] if args.folder else [p.parent for p in Path("build/mosaic").glob("*/receipt.json")]
    assert folders
    for folder in folders:
        receipt=json.loads((folder/"receipt.json").read_text())
        for name,digest in receipt["outputs"].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest
        result={name:audit(folder,name) for name in NAMES}
        print(result,flush=True)
        assert result["curved"]["orientation_error_rad"]<.01*result["baseline"]["orientation_error_rad"]
        assert result["curved"]["crossings"]<result["baseline"]["crossings"]
        renders={name:raster(folder,name,args.existing_rasters) for name in (*NAMES,"detail")}
        (folder/"oracle.json").write_text(json.dumps({"geometry":result,"renders":renders},indent=2)+"\n",encoding="utf8")


if __name__=="__main__":
    main()





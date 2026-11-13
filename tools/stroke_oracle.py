"""Independent stroke geometry, field and example statistics checks."""
import argparse
import hashlib
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ET
from collections import Counter
from itertools import combinations
from pathlib import Path
from statistics import mean

from PIL import Image, ImageChops, ImageStat

VIEWS=("hatch","tone","uniform","causal","independent","cloning","copying","sampling","scaled")
NS="{http://www.w3.org/2000/svg}"


def gap(point,a,b):
    if a==b:
        return abs(point-a)
    projection=((point-a)/(b-a)).real
    return abs(point-(a+min(1,max(0,projection))*(b-a)))


def cross(a,b):
    return (a.conjugate()*b).imag


def segment_gap(a,b,c,d):
    if cross(b-a,c-a)*cross(b-a,d-a)<0 and cross(d-c,a-c)*cross(d-c,b-c)<0:
        return 0
    return min(gap(a,c,d),gap(b,c,d),gap(c,a,b),gap(d,a,b))


def mark_segments(marks):
    for i,mark in enumerate(marks):
        points=[complex(*p) for p in mark["points"]]
        for a,b in zip(points,points[1:] if len(points)>1 else points):
            yield mark["site"],a,b,mark["width"]/2


def audit_geometry(e,folder,name):
    field,marks,a=e["field"],e["strokes"],e["controls"]
    bounds=field["bounds"]
    holes=[(complex(*h["center"]),h["radius"]) for h in field["holes"]]
    segments=list(mark_segments(marks))
    for _,p,q,r in segments:
        for v in (p,q):
            assert bounds[0]+r-1e-10<=v.real<=bounds[2]-r+1e-10
            assert bounds[1]+r-1e-10<=v.imag<=bounds[3]-r+1e-10
        assert all(gap(center,p,q)>=radius+r-1e-10 for center,radius in holes)
    sep=min(segment_gap(p,q,a,b)-r-s for (i,p,q,r),(j,a,b,s) in combinations(segments,2) if i!=j)
    required=a["clearance"] if a["mode"]=="example" else a["spacing"]
    assert sep>=required-1e-10,(name,sep,required)
    svg=ET.parse(folder/f"{name}.svg").getroot()
    paths=[p for p in svg.iter(NS+"path") if p.attrib.get("fill","none")!="none" or "stroke" in p.attrib]
    assert len(paths)==len(marks),(name,len(paths),len(marks))
    assert not list(svg.iter(NS+"image"))
    assert not re.search(rb"/Subtype\s*/Image\b",(folder/f"{name}.pdf").read_bytes())
    for p,m in zip(paths,marks):
        command=p.attrib["d"]
        if m["role"]=="dot":
            assert command.count("C")==4 and command.endswith("Z")
        else:
            assert command.count("L")==len(m["points"])-1
            assert abs(float(p.attrib["stroke-width"])-m["width"])<1e-9
    return {"strokes":len(marks),"segments":len(segments),"minimum_clearance_cm":sep}


def density(e):
    bounds=e["field"]["bounds"]
    bins=[0,0,0]
    ink=[0.,0.,0.]
    for mark in e["strokes"]:
        t=(mark["points"][0][0]-bounds[0])/(bounds[2]-bounds[0])
        i=min(2,math.floor(3*t))
        bins[i]+=1
        ink[i]+=math.pi*(mark["width"]/2)**2
    return {"counts":bins,"ink_area_cm2":ink}


def field_audit(e):
    origin=complex(*e["field"]["origin"])
    residual=0
    for _,a,b,_ in mark_segments(e["strokes"]):
        midpoint=(a+b)/2-origin
        direction=b-a
        # The analytic tangent is perpendicular to its local radial vector.
        residual=max(residual,abs((direction/midpoint).real)/abs(direction/midpoint))
    assert residual<.004
    stops=Counter(s[k] for s in e["trace"]["stops"] for k in ("forward","backward"))
    assert all(stops[k] for k in ("boundary","hole","separation","step_budget"))
    return {"maximum_normalized_tangent_error":residual,"termination_counts":stops}


def separation(a,b):
    delta=complex(*b["center"])-complex(*a["center"])
    turn=math.remainder(b["angle"]-a["angle"],math.pi)
    alpha=a["angle"]+turn/2
    axes=complex(math.cos(alpha),math.sin(alpha))
    local=delta/axes
    result={"proximity":abs(delta)}
    if a["kind"]==b["kind"]=="line":
        result.update(parallelism=2*abs(turn)/math.pi,
                      overlap=2*abs(local.real)/((a["length"]+b["length"])*math.cos(turn/2)),
                      separation=abs(local.imag))
    return result


def by_group(elements):
    results={}
    for label in sorted({v["group"] for v in elements}):
        group=[v for v in elements if v["group"]==label]
        pairs=[]
        for i,a in enumerate(group):
            if len(group)>1:
                other=min((b for j,b in enumerate(group) if i!=j),key=lambda b:math.dist(a["center"],b["center"]))
                pairs.append(separation(a,other))
        results[label]={"count":len(group),"mean_length":mean(a["length"] for a in group),
            "mean_width":mean(a["width"] for a in group),"mean_angle":mean(a["angle"] for a in group),
            "mean_proximity":mean(r["proximity"] for r in pairs) if pairs else None,
            "mean_parallelism":mean(r["parallelism"] for r in pairs) if pairs and "parallelism" in pairs[0] else None}
    return results


def example(e):
    trace=e["trace"]
    analysis=trace["analysis"]
    refs=analysis["elements"]
    marks=trace["elements"]
    seen=Counter(index for a in refs for index in a["members"])
    assert seen==Counter(range(1,len(analysis["strokes"])+1))
    assert len(analysis["merges"])==12 and len(refs)==12
    for relation in analysis["relations"]:
        a,b=refs[relation["from"]-1],refs[relation["to"]-1]
        assert a["group"]==b["group"]
        near=min(math.dist(a["center"],v["center"]) for v in refs if v is not a and v["group"]==a["group"])
        assert abs(near-relation["proximity"])<1e-10
        expected=separation(a,b)
        for key,v in expected.items():
            assert abs(relation[key]-v)<1e-10,(key,relation[key],v)
        if a["kind"]=="point":
            assert "parallelism" not in relation
    stats=by_group(marks)
    assert len(stats)==3
    copied=Counter(refs[d["source"]-1]["group"] for d in trace["decisions"] if d["kept"])
    assert copied==Counter({k:v["count"] for k,v in stats.items()})
    matched=sum(d["kept"] and d["matched"]>0 and not d["fallback"] for d in trace["decisions"])
    corrected=sum(d["kept"] and "pair" in d for d in trace["decisions"])
    return {"reference":by_group(refs),"synthesized":stats,"matched":matched,"corrected":corrected,
            "fallbacks":sum(d["fallback"] for d in trace["decisions"]),"relaxation":trace["relaxation"]}


def raster(folder,name,existing):
    w,h=384,256
    pdf,svg=[folder/f"{name}-{k}.png" for k in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-scale-to-x",str(w),"-scale-to-y",str(h),"-png","-singlefile",
                        str(folder/f"{name}.pdf"),str(pdf.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(folder/f"{name}.svg"),"--export-background=white",
                        "--export-background-opacity=1",f"--export-width={w}",f"--export-filename={svg}"],check=True)
    a,b=[Image.open(p).convert("RGB") for p in (pdf,svg)]
    assert a.size==b.size==(w,h)
    error=sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/(3*255)
    dark=[sum(im.convert("L").histogram()[:210]) for im in (a,b)]
    assert error<.04 and min(dark)>w*h*.004,(name,error,dark)
    return {"backend_mean_error":error,"pixels_darker_than_210":dark}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--folder",type=Path)
    parser.add_argument("--existing-rasters",action="store_true")
    args=parser.parse_args()
    folders=[args.folder] if args.folder else [p.parent for p in Path("build/strokes").glob("*/receipt.json")]
    assert folders
    for folder in folders:
        receipt=json.loads((folder/"receipt.json").read_text())
        for filename,sha in receipt["outputs"].items():
            assert hashlib.sha256((folder/filename).read_bytes()).hexdigest()==sha
        report={}
        for name in VIEWS:
            e=json.loads((folder/f"{name}.instance").read_text())["extensions"]["stroke"]
            item=audit_geometry(e,folder,name)
            if name=="hatch":
                item.update(field_audit(e))
            elif name in ("tone","uniform"):
                item.update(density(e))
            else:
                item.update(example(e))
            item.update(raster(folder,name,args.existing_rasters))
            report[name]=item
        tone,uniform=[report[k]["counts"] for k in ("tone","uniform")]
        assert tone[0]<tone[1]<tone[2] and tone[2]-tone[0]>uniform[2]-uniform[0]+30
        assert report["causal"]["matched"]>=10 and report["independent"]["matched"]==0
        assert report["causal"]["synthesized"]!=report["independent"]["synthesized"]
        assert report["cloning"]["corrected"]>=10
        for group,stats in report["scaled"]["synthesized"].items():
            assert abs(stats["mean_length"]/report["cloning"]["synthesized"][group]["mean_length"]-1.35)<.07
        (folder/"oracle.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf8")
        print("Stroke oracle passed:",len(report),"vector pairs;",tone,"tone bands versus",uniform)


if __name__=="__main__":
    main()

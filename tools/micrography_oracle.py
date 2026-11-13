"""Independent field, text extraction, font and vector audit for micrography."""
import argparse
import base64
import hashlib
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

NAMES=("latin","combining","greek")
NS="{http://www.w3.org/2000/svg}"
EPS=2e-8


def field_audit(ext):
    f=ext["field"]
    l=f["labels"]
    q=ext["request"]
    samples=l["samples"]
    scale=q["size"]
    weights=[]
    for a,b,w in l["edges"]:
        x,y=samples[a-1],samples[b-1]
        angle=math.acos(min(1,abs(sum(i*j for i,j in zip(x["tangent"],y["tangent"])))))
        distance=math.dist(x["point"],y["point"])
        expected=math.tanh(1-4*angle/math.pi)*math.exp(-(max(0,distance/scale-5)/10)**2)
        assert abs(w-expected)<EPS
        weights.append((a-1,b-1,w))
    assert len(weights)==66 and any(v[2]<0 for v in weights) and any(v[2]>0 for v in weights)
    for v in samples:
        trimmed=sorted(v["opposite"],key=lambda x:x["distance"])[1:-1]
        distance=sum(k["distance"] for k in trimmed)/len(trimmed)
        align=sum(k["alignment"] for k in trimmed)/len(trimmed)
        expected=max(0,align)*math.exp(-(max(0,distance/scale-5)/20)**2)
        assert abs(expected-v["attraction"])<EPS
    norm=math.sqrt(2*sum(w*w for _,_,w in weights)/sum(v["attraction"]**2 for v in samples))
    assert abs(norm-l["attraction_scale"])<EPS

    def energy(mask):
        flags=[bool(mask & (1<<i)) for i in range(len(samples))]
        return (sum(2*w for a,b,w in weights if flags[a]!=flags[b])+
                l["omega"]*norm*sum(x["attraction"] for x,active in zip(samples,flags) if not active))

    admissible=[i for i in range(1<<len(samples)) if all(bool(i & (1<<(j-1)))==bool(v) for j,v in l["fixed"])]
    optimum=min(map(energy,admissible))
    assert abs(optimum-l["energy"])<EPS and l["mask"] in admissible and len(admissible)==l["examined"]
    assert abs(energy(l["mask"])-optimum)<EPS
    assert [s["label"] for s in samples]==[int(bool(l["mask"] & (1<<i))) for i in range(len(samples))]
    assert l["energy"]<l["all_aligned"]-1e-5 and abs(energy((1<<len(samples))-1)-l["all_aligned"])<EPS
    neighbors=[set() for _ in f["points"]]
    for a,b,c in f["triangles"]:
        for x,y in ((a,b),(b,c),(c,a)):
            neighbors[x-1].add(y-1)
            neighbors[y-1].add(x-1)
    constraints={}
    for sample in samples:
        if sample["label"]:
            x,y=sample["tangent"]
            constraints[sample["node"]-1]=(x*x-y*y,2*x*y)
    residual=0
    for i,v in enumerate(f["vectors"]):
        values=[f["vectors"][j] for j in neighbors[i]]
        if i in constraints:
            values.append(constraints[i])
        expected=[sum(row[k] for row in values)/len(values) for k in range(2)]
        residual=max(residual,*[abs(a-b) for a,b in zip(v,expected)])
    assert residual<1e-8 and abs(residual-f["residual"])<EPS
    assert min(v[0] for v in f["vectors"])>.15
    return {"boundary_labels":l["mask"],"examined":l["examined"],"energy":optimum,
            "all_aligned_energy":l["all_aligned"],"minimum_representation_x":f["min_representation_x"],
            "field_residual":residual,"triangles":len(f["triangles"])}


def point_segment(p,a,b):
    v=b-a
    z=max(0,min(1,((p-a)/v).real)) if v else 0
    return abs(p-a-z*v)


def side(a,b,p):
    return ((b-a).conjugate()*(p-a)).imag


def clearance(a,b,c,d):
    if side(a,b,c)*side(a,b,d)<0 and side(c,d,a)*side(c,d,b)<0:
        return 0
    return min(point_segment(a,c,d),point_segment(b,c,d),point_segment(c,a,b),point_segment(d,a,b))


def layout_audit(x):
    e=x["extensions"]["micrography"]
    f=e["request"]["font"]
    q=e["request"]
    font=base64.b64decode(f["variants"]["opentype"]["content"],validate=True)
    assert hashlib.sha256(font).hexdigest()==f["font_sha256"]=="9b9f100958cca036fcc3102719c91ba3804a362ebc215d5ecc16d6f38d9add69"
    glyphs={g["id"]:g for g in f["glyphs"]}
    outline_fixture=glyphs["glyph/79"]["commands"]
    assert sum(k[0]=="Z" for k in outline_fixture)>=2
    originals=x["structures"]["text"]["runs"]
    assert [r["id"] for r in originals]==x["structures"]["text"]["reading_order"]
    assert "".join(r["text"] for r in originals)==q["text"]=="".join(e["clusters"])
    panel=[complex(*v) for v in q["panel"]]
    count=1
    placed=0
    angles=[]
    ink=0
    curvature=0
    prior=[]
    min_gap=math.inf
    for line in e["streamlines"]:
        points=[complex(*p) for p in line["points"]]
        delta=[b-a for a,b in zip(points,points[1:])]
        assert all(p.real>0 and abs(abs(p)-q["step"])<EPS for p in delta)
        curvature=max(curvature,*(abs(math.atan2((a/b).imag,(a/b).real))/q["step"] for a,b in zip(delta,delta[1:])))
        current=list(zip(points,points[1:]))
        for a,b in current:
            for c,d in prior:
                if c.real>b.real+q["size"]*q["spacing"] or d.real<a.real-q["size"]*q["spacing"]:
                    continue
                min_gap=min(min_gap,clearance(a,b,c,d))
        prior.extend(current)
    assert curvature<=q["max_curvature"]+EPS and min_gap>=q["size"]*q["spacing"]-EPS
    for run,positions in zip(originals,e["positions"]):
        parts=[]
        for g,(first,last) in zip(positions["glyphs"],positions["spans"]):
            assert first==count and first<=last
            count=last+1
            p=glyphs[g["glyph_ref"]]
            parts.append(p["unicode"])
            assert p["unicode"]=="".join(e["clusters"][first-1:last])
            angles.append(g["rotation"])
            z=complex(math.cos(g["rotation"]),math.sin(g["rotation"]))*q["size"]/f["units_per_em"]
            o=complex(*g["offset"])
            l,b,r,t=p["bounds"]
            corners=[o+complex(u,v)*z for u,v in ((l,b),(r,b),(r,t),(l,t))]
            assert all(side(a,b,k)>=-EPS for a,b in zip(panel,panel[1:]+panel[:1]) for k in corners)
            if p["commands"]:
                ink+=1
            placed+=1
        assert "".join(parts)==run["text"]
    assert count==len(e["clusters"])+1
    return {"runs":len(originals),"graphemes":len(e["clusters"]),"glyphs":placed,"visible_glyphs":ink,
            "minimum_line_gap_cm":min_gap,"maximum_curvature_per_cm":curvature,
            "maximum_glyph_rotation_rad":max(map(abs,angles))}


def extract(folder,name,x,local):
    target=x["extensions"]["micrography"]["request"]["text"]
    pdf=folder/f"{name}.pdf"
    if local:
        from pypdf import PdfReader
        rendered=PdfReader(pdf).pages[0].extract_text()
        extractor="pypdf glyph stream and ToUnicode"
    else:
        rendered=subprocess.check_output(["pdftotext","-raw",str(pdf),"-"]).decode("utf8")
        extractor="Poppler pdftotext -raw"
    assert rendered.split()==target.split(),(name,ascii(rendered[:250]))
    root=ET.parse(folder/f"{name}.svg").getroot()
    text=list(root.iter(NS+"text"))
    runs=["".join(t.itertext()) for t in text]
    assert "".join(runs)==target
    assert runs==[r["text"] for r in x["structures"]["text"]["runs"]]
    assert not list(root.iter(NS+"image"))
    assert not re.search(rb"/Subtype\s*/Image\b",pdf.read_bytes())
    paths=[p for p in root.iter(NS+"path") if "data-semantic-ref" in p.attrib]
    return {"pdf_words":len(rendered.split()),"pdf_extractor":extractor,"svg_runs":len(runs),"vector_glyph_paths":len(paths)}


def raster(folder,name,existing):
    w,h=832,448
    a,b=[folder/f"{name}-{k}.png" for k in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-scale-to-x",str(w),"-scale-to-y",str(h),"-png","-singlefile",
                        str(folder/f"{name}.pdf"),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(folder/f"{name}.svg"),"--export-background=white","--export-background-opacity=1",
                        f"--export-width={w}",f"--export-filename={b}"],check=True)
    pdf,svg=[Image.open(p).convert("RGB") for p in (a,b)]
    assert pdf.size==svg.size==(w,h)
    error=sum(ImageStat.Stat(ImageChops.difference(pdf,svg)).mean)/(3*255)
    assert error<.025
    dark=[sum(v.convert("L").histogram()[:190]) for v in (pdf,svg)]
    assert min(dark)>1000
    return {"mean_backend_error":error,"ink_pixels":dark}


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--folder",type=Path)
    p.add_argument("--existing-rasters",action="store_true")
    p.add_argument("--local-pdf-extractor",action="store_true")
    args=p.parse_args()
    folders=[args.folder] if args.folder else [x.parent for x in Path("build/micrography").glob("*/receipt.json")]
    assert folders
    for folder in folders:
        receipt=json.loads((folder/"receipt.json").read_text())
        for name,sha in receipt["outputs"].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==sha
        results={}
        for name in NAMES:
            x=json.loads((folder/f"{name}.instance").read_text(encoding="utf8"))
            e=x["extensions"]["micrography"]
            result=field_audit(e)|layout_audit(x)|extract(folder,name,x,args.local_pdf_extractor)
            assert result["visible_glyphs"]==result["vector_glyph_paths"]
            result.update(raster(folder,name,args.existing_rasters))
            results[name]=result
        assert results["combining"]["maximum_curvature_per_cm"]>1e-4
        failures=json.loads((folder/"failures.json").read_text())
        assert failures["space"]["solver"]["status"]=="insufficient_space"
        assert failures["size"]["solver"]["status"]=="size_below_minimum"
        (folder/"oracle.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf8")
        print("Micrography oracle passed",sum(r["graphemes"] for r in results.values()),"graphemes and",len(results),"render pairs")


if __name__=="__main__":
    main()

"""Independent collection contract, port, hierarchy, text and replay audit."""
import collections
import hashlib
import json
import math
from pathlib import Path
import argparse
import subprocess
import re
import xml.etree.ElementTree as ET


def audit(folder,local_pdf_extractor=False):
    def read(name):
        return json.loads((folder/name).read_text(encoding="utf8"))
    receipt=read("receipt.json")
    for name,sha in receipt["outputs"].items():
        assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==sha,name
    data=read("original-collection.json")
    assert data["schema"]=="florilegium-original-collection@1"
    members={}
    for m in data["members"]:
        assert re.fullmatch(r"[A-Za-z0-9_-]{1,64}",m["id"])
        assert m["recipe_file"]==m["id"]+".recipe" and m["instance_file"]==m["id"]+".instance"
        assert hashlib.sha256((folder/m["recipe_file"]).read_bytes()).hexdigest()==m["recipe_sha256"]
        assert hashlib.sha256((folder/m["instance_file"]).read_bytes()).hexdigest()==m["instance_sha256"]
        assert m["validation"]["status"]=="passed"
        members[m["id"]]=read(m["instance_file"])
    bare=members["penrose"]
    points={p["id"]:p["point"] for p in bare["structures"]["tiling"]["vertices"]}
    edges={e["id"]:e for e in bare["structures"]["tiling"]["edges"]}
    cells={c["id"]:c for c in bare["structures"]["tiling"]["cells"]}
    port_data=read("ports.json")
    assert port_data["frame"]==bare["frame"]
    ports=collections.defaultdict(list)
    for port in port_data["ports"]:
        edge=edges[port["edge"]]
        a,b=points[edge["from"]],points[edge["to"]]
        assert port["point"]==[(a[i]+b[i])/2 for i in (0,1)]
        assert abs(sum((b[i]-a[i])*port["inward"][i] for i in (0,1)))<1e-10
        assert math.isclose(math.hypot(*port["inward"]),1)
        assert port["cell"] in cells and port["frame"]==bare["frame"]["id"]
        ports[port["edge"]].append(port)
    paired=0
    for group in ports.values():
        assert len(group) in (1,2)
        if len(group)==2:
            a,b=group
            assert a["point"]==b["point"] and a["width_cm"]==b["width_cm"]
            assert a["inward"]==[-v for v in b["inward"]]
            assert a["paired"] and b["paired"]
            paired+=1
    assert paired>30
    paths=ET.parse(folder/"decorated.svg").getroot().iter("{http://www.w3.org/2000/svg}path")
    painted=collections.defaultdict(list)
    number=r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"
    for path in paths:
        if "C" in path.attrib.get("d",""):
            painted[path.attrib["data-semantic-ref"]].append(
                [float(v) for v in re.findall(number,path.attrib["d"])])
    for port in port_data["ports"]:
        candidates=[p for p in painted[port["cell"]] if math.dist(p[:2],port["point"])<1e-8]
        assert len(candidates)==1
        p=candidates[0]
        tangent=[p[2]-p[0],p[3]-p[1]]
        assert abs(tangent[0]*port["inward"][1]-tangent[1]*port["inward"][0])<1e-8
        assert sum(tangent[i]*port["inward"][i] for i in (0,1))>0
    detail=read("detail.json")
    assert port_data["source_sha256"]==hashlib.sha256((folder/"penrose.instance").read_bytes()).hexdigest()
    spatial=members["spectre"]
    assert detail["source_sha256"]==hashlib.sha256((folder/"spectre.instance").read_bytes()).hexdigest()
    assert detail["hierarchy"]==spatial["structures"]["tiling"]["hierarchy"]
    cells={c["id"]:c for c in spatial["structures"]["tiling"]["cells"]}
    for a in detail["annotations"]:
        c=cells[a["ref"]]
        assert a["prototype"]==c["prototype"] and a["chirality"]==c["chirality"]
    groups={g["id"]:g for g in detail["hierarchy"]}
    assert len(groups)>1
    centers={a["ref"]:a["point"] for a in detail["annotations"]}
    centers.update({g["ref"]:g["point"] for g in detail["groups"]})
    for g in detail["groups"]:
        assert g["children"]==groups[g["ref"]]["children"]
        for i in (0,1):
            assert abs(g["point"][i]-sum(centers[c][i] for c in g["children"])/len(g["children"]))<1e-10
    detail_refs={p.attrib.get("data-semantic-ref") for p in ET.parse(folder/"detail.svg").getroot().iter(
        "{http://www.w3.org/2000/svg}path")}
    assert set(groups)<=detail_refs
    placements=[]
    for page in data["products"]["pages"]:
        panel=next(p for p in page["panels"] if p["id"]=="spread")
        view=next(r["view"] for r in data["products"]["renders"] if r["id"]==panel["render_ref"])
        b,slot=view["crop"],panel["bounds"]
        scale=min((slot[2]-slot[0])/(b[2]-b[0]),(slot[3]-slot[1])/(b[3]-b[1]))
        tx=(slot[0]+slot[2]-scale*(b[0]+b[2]))/2
        ty=(slot[1]+slot[3]-scale*(b[1]+b[3]))/2
        placements.append((scale,tx,ty))
    assert math.isclose(placements[0][1],16) and math.isclose(placements[1][1],0)
    assert placements[0][0]==placements[1][0] and placements[0][2]==placements[1][2]
    knot=members["hybrid"]
    attachment=knot["extensions"]["celtic"]["attachment"]
    port=next(p for p in knot["structures"]["strands"]["ports"] if p["id"]==attachment["port"])
    assert port["point"]==attachment["root"]==attachment["points"][0]
    assert len(attachment["points"])>=3
    if local_pdf_extractor:
        from pypdf import PdfReader
        text="".join(page.extract_text() for page in PdfReader(folder/"collection.pdf").pages)
        extractor="pypdf glyph stream and ToUnicode"
    else:
        text=subprocess.check_output(["pdftotext","-raw",str(folder/"collection.pdf"),"-"]).decode("utf8")
        extractor="Poppler pdftotext -raw"
    assert re.sub(r"\s","",text)=="AIAII",repr(text)
    for i in (1,2):
        info=subprocess.check_output(["pdfinfo",str(folder/f"collection-{i}.pdf")]).decode()
        match=re.search(r"Page size:\s+([0-9.]+) x ([0-9.]+)",info)
        assert match and abs(float(match[1])*2.54/72-16)<.002 and abs(float(match[2])*2.54/72-20)<.002
    out={"source_digest":receipt["source_digest"],"members":len(members),"paired_edges":paired,
         "detail_annotations":len(detail["annotations"]),"searchable_text":text.strip(),"pages":2,
         "pdf_extractor":extractor}
    (folder/"oracle.json").write_text(json.dumps(out,indent=2)+"\n",encoding="utf8")
    print(out)


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("folder",type=Path,nargs="?")
    p.add_argument("--local-pdf-extractor",action="store_true")
    args=p.parse_args()
    folders=[args.folder] if args.folder else sorted(p.parent for p in Path("build/collection").glob("*/receipt.json"))
    assert folders
    for folder in folders:
        audit(folder,args.local_pdf_extractor)

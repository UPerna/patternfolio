"""Independent checks of Hat polykites and bounded marked-square witnesses."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat

VIEWS = ("whole", "detail-kites", "crop-a", "crop-b", "common-a", "common-b", "completion")
ROOT = Path(__file__).resolve().parent.parent


def load(folder, name):
    return json.loads((folder/name).read_text(encoding="utf-8"))


def walk(points):
    return zip(points, points[1:]+points[:1])


def twice_area(points):
    return sum(a[0]*b[1]-a[1]*b[0] for a,b in walk(points))


def undirected(a,b):
    return tuple(sorted((tuple(a),tuple(b))))


def parentage(instance):
    nodes = instance["extensions"]["hat"]["hierarchy"]
    children = {tuple(k):tuple(n["address"]) for n in nodes for k in n["children"]}
    assert () not in children
    assert sum(len(n["children"]) for n in nodes)==len(children)
    for n in nodes:
        a=tuple(n["address"])
        if a:
            assert children[a]==tuple(n["parent"])==a[:-1]
    for c in instance["structures"]["tiling"]["cells"]:
        a=tuple(c["address"])
        assert children[a]==tuple(c["parent_address"])==a[:-1]
    return len(nodes)


def reference_hash(tiles):
    lines=[]
    for c in tiles:
        address=".".join(map(str,c["address"]))
        coordinates=";".join(f"{x},{y}" for x,y in c["outline"])
        chirality="-" if c["chirality"]<0 else "+"
        lines.append(f'{address}:{c["label"]}:{chirality}:{coordinates}')
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()


def hat_patch(instance):
    t=instance["structures"]["tiling"]
    cells=t["cells"]
    vertices={v["id"]:tuple(v["lattice"]) for v in t["vertices"]}
    edges={e["id"]:e for e in t["edges"]}
    signatures=set()
    centers=set()
    owners=defaultdict(set)
    length_classes=Counter()
    for c in cells:
        assert len(c["outline"])==13 and len(c["kites"])==8
        assert twice_area(c["outline"])==32*c["chirality"]
        assert c["isometry"]["reflection"]==(c["chirality"]==-1)
        assert (c["label"]=="H1")==c["isometry"]["reflection"]
        local=Counter()
        for kite in c["kites"]:
            assert twice_area(kite)==4*c["chirality"]
            u,v=kite[0]
            centers.add(((2*u+v)%6,(v-u)%6))
            shape=tuple(sorted(map(tuple,kite)))
            assert shape not in signatures
            signatures.add(shape)
            lengths=[]
            for a,b in walk(kite):
                x,y=a[0]-b[0],a[1]-b[1]
                lengths.append(x*x+x*y+y*y)
                local[undirected(a,b)]+=1
            assert sorted(lengths)==[1,1,3,3]
        assert set(local.values())<={1,2}
        boundary={side for side,n in local.items() if n==1}
        measured=set()
        points=[]
        for e in c["boundary"]:
            side=edges[e["edge"]]
            a,b=(vertices[side[k]] for k in ("from","to"))
            measured.add(undirected(a,b))
            points.append(b if e["reversed"] else a)
            owners[e["edge"]].add(c["id"])
            dx,dy=b[0]-a[0],b[1]-a[1]
            length_classes[dx*dx+dx*dy+dy*dy]+=1
        assert boundary==measured and twice_area(points)==32
    assert len(centers)==1 and len(signatures)==8*len(cells)
    assert set(length_classes)=={1,3}
    for eid,e in edges.items():
        present=owners[eid]
        assert len(present) in (1,2) and e["owner"]==min(present)
        assert present<=set(e["global_cells"])
        assert e["global_owner"]==min(e["global_cells"])
    return {"leaves":len(cells),"kites":len(signatures),"hierarchy_nodes":parentage(instance),
            "reflected":sum(c["chirality"]<0 for c in cells)}


MARKS={"blank":set(),"straight-ns":{"north","south"},"straight-ew":{"east","west"},
       "elbow-ne":{"north","east"},"elbow-es":{"east","south"},
       "elbow-sw":{"south","west"},"elbow-wn":{"west","north"}}
SIDES=(("north",0,1,"south"),("east",1,0,"west"),
       ("south",0,-1,"north"),("west",-1,0,"east"))


def solver(folder):
    x=load(folder,"completion.instance")
    e=x["extensions"]["constraint"]
    problem=e["input"]
    placed={tuple(map(int,r["cell"].split("/"))):MARKS[r["tile"]] for r in e["assignment"]}
    expected={(i,j) for i in range(1,problem["width"]+1) for j in range(1,problem["height"]+1)}
    expected-=set(map(tuple,problem["holes"]))
    assert set(placed)==expected and len(e["assignment"])==len(expected)
    fixed={(tuple(r["cell"]),r["side"]):r["mark"] for r in problem["boundary"]}
    exits=[]
    for (i,j),marks in placed.items():
        for name,dx,dy,opposite in SIDES:
            neighbor=(i+dx,j+dy)
            active=name in marks
            if neighbor in placed:
                assert active==(opposite in placed[neighbor])
            else:
                assert active==fixed.get(((i,j),name),0)
                if active:
                    exits.append((2*i-1+dx,2*j-1+dy))
    assert len(exits)==2
    graph=x["structures"]["graph"]
    vertices={v["id"]:tuple(v["grid"]) for v in graph["vertices"]}
    links=defaultdict(set)
    for edge in graph["edges"]:
        a,b=vertices[edge["from"]],vertices[edge["to"]]
        links[a].add(b);links[b].add(a)
    assert {p for p,neighbors in links.items() if len(neighbors)==1}==set(exits)
    assert all(len(n) in (1,2) for n in links.values())
    seen={exits[0]}
    queue=list(seen)
    for p in queue:
        for q in links[p]-seen:
            seen.add(q);queue.append(q)
    assert exits[1] in seen and set(links)==seen
    statuses={}
    for name in ("completion","replay","unsatisfiable","unknown","timeout"):
        r=load(folder,name+".solver.json")
        state="complete" if name in ("completion","replay") else name
        assert r["solver"]["status"]==state
        assert r["outputs"]==(2 if state=="complete" else 0)
        assert r["status"]==("complete" if state=="complete" else "failed")
        for path in folder.glob(name+"-*.build.json"):
            raw=load(folder,path.name)
            assert raw["extensions"]["solver"]==r["solver"] and len(raw["outputs"])==r["outputs"]
        statuses[name]=r["solver"]
    assert statuses["replay"]["nodes"]==statuses["unknown"]["nodes"]==0
    assert statuses["timeout"]["deadline_ms"]==2
    assert statuses["completion"]["assignment_sha256"]==statuses["replay"]["assignment_sha256"]
    unsat=load(folder,"unsatisfiable.recipe")["design"]["inputs"]["problem"]
    # Every permitted tile contributes zero or two marks. An internal
    # mark is counted twice, so one boundary mark is impossible.
    assert sum(r["mark"] for r in unsat["boundary"])==1
    assert load(folder,"unknown.recipe")["design"]["parameters"]["node_limit"]==0
    assert load(folder,"timeout.recipe")["design"]["parameters"]["deadline_ms"]==2
    assert load(folder,"replay.recipe")["design"]["inputs"]["assignment"]==e["assignment"]
    return {"occupied":len(expected),"path_vertices":len(seen),"statuses":statuses}


def raster(folder,name,existing):
    view=[float(n) for n in ET.parse(folder/(name+".svg")).getroot().attrib["viewBox"].split()]
    # Match the positive half-pixel rounding used by the render harness.
    w,h=int(view[2]*50+.5),int(view[3]*50+.5)
    a,b=[folder/f"{name}-{backend}.png" for backend in ("pdf","svg")]
    if not existing:
        subprocess.run(["pdftoppm","-r","127","-W",str(w),"-H",str(h),"-png","-singlefile",
                        str(folder/(name+".pdf")),str(a.with_suffix(""))],check=True)
        subprocess.run(["inkscape",str(folder/(name+".svg")),"--export-background=white",
                        "--export-background-opacity=1",f"--export-width={w}",f"--export-filename={b}"],check=True)
    images=[Image.open(p).convert("RGB") for p in (a,b)]
    assert all(im.size==(w,h) for im in images),(name,(w,h),[im.size for im in images])
    mean=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
    ink=[sum(im.convert("L").histogram()[:220]) for im in images]
    assert mean<.05 and min(ink)>100,(name,mean,ink)
    return {"dimensions":[w,h],"mean_backend_error":mean,"ink_pixels":ink}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--folder",type=Path)
    parser.add_argument("--existing-rasters",action="store_true")
    args=parser.parse_args()
    folders=[args.folder] if args.folder else [p.parent for p in Path("build/hat").glob("*/receipt.json")]
    assert folders
    reference=load(ROOT/"docs/validation/fixtures","hat-reference-hashes.json")
    for folder in folders:
        receipt=load(folder,"receipt.json")
        for name,digest in receipt["outputs"].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,name
        certificates=load(folder,"cluster-certificates.json")
        for r in reference:
            c=certificates[r["root"]+str(r["depth"])]
            assert (c["reference_hash"],c["tiles"],c["reflected"])==(r["hash"],r["count"],r["reflected"])
            assert c["area2"]==32*r["count"] and c["kites"]==8*r["count"]
        instances={n:load(folder,n+".instance") for n in ("whole","detail","crop-a","crop-b")}
        results={n:hat_patch(x) for n,x in instances.items()}
        for name,tag in (("whole","H3"),("detail","H2")):
            assert reference_hash(instances[name]["structures"]["tiling"]["cells"])==certificates[tag]["reference_hash"]
        full={c["id"]:c for c in instances["whole"]["structures"]["tiling"]["cells"]}
        root_edges={e["id"]:e["global_cells"] for e in instances["whole"]["structures"]["tiling"]["edges"]}
        subset=[]
        for n in ("crop-a","crop-b"):
            t=instances[n]["structures"]["tiling"]
            assert all(full[c["id"]]==c for c in t["cells"])
            assert all(root_edges[e["id"]]==e["global_cells"] for e in t["edges"])
            assert any(e["boundary_reason"]=="query_cut" for e in t["edges"])
            subset.append({c["id"] for c in t["cells"]})
        assert len(subset[0]&subset[1])==receipt["shared"]
        result={"hat":results,"reference_clusters":len(reference),"shared":receipt["shared"],"bounded":solver(folder),
                "renders":{n:raster(folder,n,args.existing_rasters) for n in VIEWS}}
        for backend in ("pdf","svg"):
            a,b=[Image.open(folder/f"common-{n}-{backend}.png").convert("RGB") for n in ("a","b")]
            assert ImageChops.difference(a,b).getbbox() is None
        (folder/"oracle.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
        print("Hat and finite constraint oracle:",results["whole"],len(reference),"reference clusters",
              receipt["shared"],"shared hats,",len(VIEWS),"backend pairs")


if __name__=="__main__":
    main()

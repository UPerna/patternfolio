"""Independent checks for the five-family fixture and its shared exports."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat


def load(folder, name):
    return json.loads((folder / name).read_text(encoding="utf-8"))


def audit_semantics(folder):
    def instance(name):
        return load(folder, name + ".instance")

    botanical = instance("botanical")
    nodes = {n["id"]: n for n in botanical["structures"]["growth"]["nodes"]}
    attached = [n for n in nodes.values() if "parent" in n]
    assert len(attached) == 14
    for node in attached:
        parent = nodes[node["parent"]]
        endpoint = parent["controls"][-1] if "controls" in parent else parent["point"]
        assert max(abs(a-b) for a,b in zip(node["point"],endpoint)) <= 1e-12
    assert len(botanical["extensions"]["panel"]["region"]) == 5

    strands = instance("celtic")["structures"]["strands"]
    encounters = {}
    for component in strands["components"]:
        for encounter in component["encounters"]:
            encounters.setdefault(encounter["crossing"], {})[encounter["role"]] = component["id"]
    assert len(strands["crossings"]) == 10
    for crossing in strands["crossings"]:
        assert encounters[crossing["id"]] == {"over": crossing["over"], "under": crossing["under"]}
        assert crossing["over_branch"] != crossing["under_branch"]

    pic = instance("islamic")
    vertices = {v["id"] for v in pic["structures"]["graph"]["vertices"]}
    contacts = [p for p in pic["extensions"]["pic"]["contacts"] if p["role"] == "interior"]
    assert contacts and all(p["id"] in vertices and len(p["faces"]) == 2 for p in contacts)

    penrose = instance("penrose")["structures"]["tiling"]
    assert {c["prototype"] for c in penrose["cells"]} == {"thin", "thick"}
    assert all(e["matching"]["multiplicity"] in (1, 2) for e in penrose["edges"])
    assert {e["matching"]["multiplicity"] for e in penrose["edges"]} == {1, 2}

    spectre = instance("spectre")["structures"]["tiling"]
    assert len(spectre["cells"]) == 62
    assert all(c["chirality"] == 1 and not c["isometry"]["reflection"] for c in spectre["cells"])
    root = ET.parse(folder / "spectre-diagnostic.svg")
    assert any("C" in p.attrib.get("d","") for p in root.iter("{http://www.w3.org/2000/svg}path"))
    return {"attachments": len(attached), "crossings": len(encounters), "pic_contacts": len(contacts),
            "penrose_cells": len(penrose["cells"]), "spectre_cells": len(spectre["cells"])}


def raster(folder, name, existing):
    page = int(name[-1]) if name.startswith("composition-") else 1
    pdf = folder / ("composition.pdf" if name.startswith("composition-") else name + ".pdf")
    svg = folder / (name + ".svg")
    box = [float(x) for x in ET.parse(svg).getroot().attrib["viewBox"].split()]
    w, h = round(box[2]*50), round(box[3]*50)
    a, b = [folder / f"{name}-{backend}.png" for backend in ("pdf", "svg")]
    if not existing:
        subprocess.run(["pdftoppm", "-r", "127", "-f", str(page), "-l", str(page),
                        "-W", str(w), "-H", str(h), "-png", "-singlefile", str(pdf),
                        str(a.with_suffix(""))], check=True)
        subprocess.run(["inkscape", str(svg), "--export-background=white", "--export-background-opacity=1",
                        f"--export-width={w}", f"--export-filename={b}"], check=True)
    images = [Image.open(p).convert("RGB") for p in (a, b)]
    assert all(im.size == (w,h) for im in images), (name, [im.size for im in images], (w,h))
    mean = sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
    ink = [sum(im.convert("L").histogram()[:220]) for im in images]
    assert mean < .06 and min(ink) > 100, (name, mean, ink)
    return images, {"mean_backend_error": mean, "ink_pixels": ink, "dimensions": [w,h]}


def protected_ink(images, rect, height):
    x0,y0,x1,y1 = rect
    pixel_box = (round(x0*50)+2,round((height-y1)*50)+2,round(x1*50)-2,round((height-y0)*50)-2)
    return [sum(im.crop(pixel_box).convert("L").histogram()[:245]) for im in images]


def placed_box(box, size, slot):
    x0,y0,x1,y1 = slot
    width,height = size
    scale = min((x1-x0)/width,(y1-y0)/height)
    dx = (x0+x1-scale*width)/2
    dy = (y0+y1-scale*height)/2
    return [coordinate*scale + offset for coordinate,offset in zip(box,(dx,dy,dx,dy))]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing-rasters", action="store_true")
    parser.add_argument("--folder", type=Path)
    args = parser.parse_args()
    folders = [args.folder] if args.folder else [p.parent for p in Path("build/integration").glob("*/receipt.json")]
    assert folders, "run integrationcheck first"
    for folder in folders:
        receipt = load(folder, "receipt.json")
        assert receipt["checks"] >= 46
        for name, digest in receipt["outputs"].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest() == digest, name
        semantics = audit_semantics(folder)
        info = subprocess.check_output(["pdfinfo", str(folder/"composition.pdf")], text=True)
        assert any(line.startswith("Pages:") and line.split()[-1] == "2" for line in info.splitlines())
        results, images = {}, {}
        for name in ("botanical","celtic","islamic","penrose","spectre"):
            for variant in (name, name+"-diagnostic"):
                images[variant],results[variant] = raster(folder,variant,args.existing_rasters)
            assert ImageChops.difference(images[name][0],images[name+"-diagnostic"][0]).getbbox()
        for name in ("composition-1","composition-2","islamic-unmasked"):
            images[name],results[name] = raster(folder,name,args.existing_rasters)
        masks = {"botanical": ([6,4,7,5.2], (12,11), (.8,.8,9.7,14.2)),
                 "islamic": ([3.3,1.58,3.8,2.1], (5.4,3.6), (10.3,.8,19.2,7.35))}
        for name,(box,size,slot) in masks.items():
            assert receipt["families"][name]["mask"] == box, name
            assert protected_ink(images[name],box,size[1]) == [0,0], name
            assert protected_ink(images["composition-1"],placed_box(box,size,slot),15) == [0,0], name
        unmasked = protected_ink(images["islamic-unmasked"], masks["islamic"][0], masks["islamic"][1][1])
        assert min(unmasked) > 0, unmasked
        evidence = {"semantics": semantics, "render": results, "protected_probe_unmasked_ink": unmasked}
        (folder/"oracle.json").write_text(json.dumps(evidence,indent=2)+"\n",encoding="utf-8")
        print("Five-family independent checks:", semantics, len(results), "backend comparisons")


if __name__ == "__main__":
    main()

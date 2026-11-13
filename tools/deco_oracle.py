"""Audit serialized DecoBrush geometry, edit locality and actual SVG paths."""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from xml.etree import ElementTree

NAMES = ("floral", "geometric", "branched", "branched-edit")


def signed_area(ring):
    return sum(a[0] * b[1] - a[1] * b[0]
               for a, b in zip(ring, ring[1:] + ring[:1])) / 2


def rendered_rings(path):
    root = ElementTree.parse(path).getroot()
    operations = [p for p in root.iter("{http://www.w3.org/2000/svg}path")
                  if "data-semantic-ref" in p.attrib]
    assert len(operations) == 1
    rings = []
    for segment in operations[0].attrib["d"].split("Z")[:-1]:
        coords = re.findall(r"[ML]\s*([-+.\deE]+)\s+([-+.\deE]+)", segment)
        rings.append([(float(x), float(y)) for x, y in coords])
    return rings


def audit(folder):
    receipt = json.loads((folder / "receipt.json").read_bytes())
    assert receipt["checks"] == 8
    for name, digest in receipt["outputs"].items():
        assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == digest, name
    evidence = {}
    fields = {}
    for name in NAMES:
        data = json.loads((folder / (name + ".instance")).read_bytes())
        ext = data["extensions"]["decobrush"]
        field = ext["field"]
        fields[name] = ext
        rings = ext["contours"]
        areas = [signed_area(ring) for ring in rings]
        assert sum(a > 0 for a in areas) == 1, name
        assert math.isclose(sum(areas), ext["area"]["filled_area"], abs_tol=1e-9)
        rendered = rendered_rings(folder / (name + ".svg"))
        assert rendered == [[tuple(p) for p in ring] for ring in rings]
        assert (folder / (name + ".pdf")).read_bytes().startswith(b"%PDF-")
        cuts = [s["certificate"] for s in field["seams"]]
        assert len(cuts) == 2 and all(c["flow"] == c["energy"] <= c["straight_energy"] for c in cuts)
        assert all(.45 < m["min_jacobian"] and .55 <= m["min_stretch"] <= m["max_stretch"] <= 1.6
                   and m["residual"] <= .025 for m in field["deformation"])
        accepted = sum(level["accepted"] for level in ext["synthesis"]["levels"])
        assert accepted > 0
        pieces = [ext["request"]["library"][m["piece"] - 1]["role"] for m in field["matches"]]
        assert pieces == ["start", "middle", "finish"]
        width, height = field["width"], field["height"]
        spine = field["grid"][(height // 2) * width:(height // 2 + 1) * width]
        # A fixed middle stamp has ink at both nominal endpoints. The matched
        # start and finish exemplars deliberately leave those endpoints clear.
        assert spine[0]["source"]["distance"] > 0 and spine[-1]["source"]["distance"] > 0
        assert all(p["source"]["distance"] < 0 for p in spine[3:-3])
        evidence[name] = {"area": sum(areas), "outer_boundaries": 1, "holes": len(areas) - 1,
                          "cut_energies": cuts, "coherent_corrections": accepted, "piece_roles": pieces,
                          "endpoint_ink_count": 0, "fixed_middle_stamp_endpoint_ink_count": 2}

    original, edited = fields["branched"], fields["branched-edit"]
    left, bottom, right, top, ink = edited["request"]["edit"][0]
    changed = 0
    for a, b in zip(original["field"]["grid"], edited["field"]["grid"], strict=True):
        assert (a["x"], a["y"]) == (b["x"], b["y"])
        if left <= a["x"] <= right and bottom <= a["y"] <= top:
            changed += a["source"] != b["source"]
            assert (b["source"]["distance"] < 0) == ink
        else:
            assert a["source"] == b["source"]
    assert changed > 0 and evidence["branched-edit"]["area"] < evidence["branched"]["area"]
    assert len({evidence[k]["area"] for k in NAMES[:3]}) == 3
    assert evidence["geometric"]["holes"] >= 1
    baseline = ElementTree.parse(folder / "fixed-stamp.svg").getroot()
    stamps = [p for p in baseline.iter("{http://www.w3.org/2000/svg}path") if "data-semantic-ref" in p.attrib]
    assert len(stamps) == 21 and (folder / "fixed-stamp.pdf").read_bytes().startswith(b"%PDF-")
    return {"fixed_stamp_paths":len(stamps), "source_digest": receipt["source_digest"], "edited_samples": changed, "fixtures": evidence}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path, nargs="?")
    args = parser.parse_args()
    folders = [args.folder] if args.folder else sorted(p.parent for p in Path("build/decobrush").glob("*/receipt.json"))
    assert folders, "missing DecoBrush receipts"
    for folder in folders:
        report = json.dumps(audit(folder), indent=2, sort_keys=True) + "\n"
        (folder / "oracle.json").write_text(report, encoding="utf8")
        print(folder, "verified")



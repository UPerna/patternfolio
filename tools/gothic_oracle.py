"""Verify spatial compass constraints, sample bounds and exact camera correspondence."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path


def audit(folder):
    def read(name):
        return json.loads((folder / name).read_text(encoding="utf8"))

    receipt = read("receipt.json")
    for name, expected in receipt["outputs"].items():
        assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == expected, name
    totals = collections.Counter()
    for name, views in (("canonical", ["top", "front", "oblique"]), ("edited", ["edited"])):
        data = read(name + ".network.json")
        assert data["schema"] == "florilegium-curve-network@1"
        assert data["frame"]["dimension"] == 3 and data["frame"]["unit"] == "cm"
        units = {u["id"]: u for u in data["construction"]["units"]}
        points = {v["id"]: v["point"] for v in data["network"]["vertices"]}
        curves = {c["id"]: c for c in data["network"]["curves"]}
        tolerance = data["construction"]["chord_tolerance_cm"]
        for uid, u in units.items():
            seen = set()
            for node in u["construction"]:
                assert set(node.get("dependencies", [])) <= seen
                seen.add(node["id"])
            side = u["side"]
            lo, hi = side["lower"], side["upper"]
            assert math.isclose(math.dist(lo["center"], hi["center"]), lo["radius"] + hi["radius"])
            assert math.isclose(lo["center"][0], lo["radius"])
            assert math.isclose(side["length"] - hi["center"][0], hi["radius"])
            for arc in (lo, hi):
                assert math.isclose(math.dist(side["join"], arc["center"]), arc["radius"])
            if "support" in u:
                assert u["origin"] == points[u["support"]]
                assert curves[uid + "/curve/1"]["from"] == u["support"]
                totals["nested_supports"] += 1
            else:
                assert u["origin"][2] == 0
            for crossing in u["crossings"]:
                a, b = (curves[f"{uid}/curve/{crossing[key]}"] for key in ("first", "second"))
                pa, pb = (points[next(s["vertex"] for s in c["samples"]
                                      if abs(s["x"] - crossing[key]) < 1e-8)]
                          for c, key in ((a, "a"), (b, "b")))
                assert math.dist(pa[:2], crossing["top"]) < 1e-8
                assert math.dist(pb[:2], crossing["top"]) < 1e-8
                assert math.isclose(pa[2], crossing["first_height"])
                assert math.isclose(pb[2], crossing["second_height"])
                assert crossing["joined"] == (math.dist(pa, pb) < 1e-8)
                if crossing["joined"]:
                    assert pa == pb == points[crossing["id"]]
                totals["junctions" if crossing["joined"] else "separate_depth_crossings"] += 1
        for c in curves.values():
            u = units[c["unit"]]
            r = u["replicas"][c["replica"] - 1]
            samples = c["samples"]
            assert c["from"] == samples[0]["vertex"] and c["to"] == samples[-1]["vertex"]
            for sample in samples:
                x, y, z = points[sample["vertex"]]
                assert all(map(math.isfinite, (x, y, z)))
                assert abs(r["sx"] * (x - r["x"]) - sample["x"]) < 1e-8
                assert math.isclose(math.hypot(x-r["x"], y-r["y"]), u["circle"]["radius"])
                offset = sample["x"] - u["start"]
                side = u["side"]
                arc = side["lower"] if offset <= side["join"][0] else side["upper"]
                assert math.isclose(math.dist([offset,z-u["origin"][2]], arc["center"]), arc["radius"])
                totals["spatial_samples"] += 1
            for a, b in zip(samples, samples[1:]):
                assert a["x"] < b["x"]
                p, q = points[a["vertex"]], points[b["vertex"]]
                for t in (.125, .25, .5, .75, .875):
                    x = a["x"] + (b["x"]-a["x"])*t
                    arc = side["lower"] if x-u["start"] <= side["join"][0] else side["upper"]
                    cx, cz = arc["center"]
                    direction = 1 if arc is side["lower"] else -1
                    z = u["origin"][2] + cz + direction * math.sqrt(max(0,arc["radius"]**2-(x-u["start"]-cx)**2))
                    y = r["y"] + r["sy"] * math.sqrt(u["circle"]["radius"]**2-x*x)
                    assert math.hypot(y-(p[1]+t*(q[1]-p[1])), z-(p[2]+t*(q[2]-p[2]))) <= tolerance
                    totals["chord_probes"] += 1
        for view in views:
            settings = read(view+".view")
            projection = settings["projection"]
            m = projection["matrix"]
            scene = read(view+".scene")
            assert scene["validity"] == "visualization_only"
            def project(p):
                return [sum(m[4*i+j]*p[j] for j in range(3))+m[4*i+3] for i in range(3)]
            if projection["depth_policy"] == "depth_sorted":
                expected = []
                for cid, c in curves.items():
                    coords = [project(points[s["vertex"]]) for s in c["samples"]]
                    for i, (a,b) in enumerate(zip(coords, coords[1:])):
                        expected.append((math.floor((a[2]+b[2])/2*1e8+.5), cid, i, [a,b]))
                expected.sort(key=lambda segment: segment[:3])
                expected = [(cid, coords) for _,cid,_,coords in expected]
            else:
                expected = [(cid,[project(points[s["vertex"]]) for s in c["samples"]])
                            for cid,c in curves.items()]
            assert len(scene["operations"]) == len(expected)
            for operation, (cid, coords) in zip(scene["operations"], expected):
                assert operation["semantic_ref"] == cid and len(operation["commands"]) == len(coords)
                for command, point in zip(operation["commands"], coords):
                    assert math.dist(command[1:], point[:2]) < 1e-10
                    left, bottom, right, top = settings["crop"]
                    assert left+.02 < point[0] < right-.02 and bottom+.02 < point[1] < top-.02
                    totals["projected_samples"] += 1
    assert totals["junctions"] and totals["separate_depth_crossings"] and totals["nested_supports"] == 2
    result = {"source_digest":receipt["source_digest"], **totals}
    (folder/"oracle.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf8")
    print(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path, nargs="?")
    args = parser.parse_args()
    folders = [args.folder] if args.folder else sorted(p.parent for p in Path("build/gothic").glob("*/receipt.json"))
    assert folders, "missing Gothic acceptance outputs"
    for folder in folders:
        audit(folder)

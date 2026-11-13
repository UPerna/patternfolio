"""Rebuild the shipped documents through both native and observed entrypoints."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from PIL import ImageChops
from build import build, ROOT
from enginecheck import raster

DOCUMENTS = ("florilegium", "florilegium-grow", "showcase", "book-demo",
             "asset-demo", "folio-demo", "specimen")

def text(pdf):
    return subprocess.check_output(["pdftotext", "-layout", str(pdf), "-"])

def compare(folder, name, engine):
    source = ROOT / (name + ".tex")
    target = folder / (name + "-" + engine)
    native = build(source, engine, target / "native")
    wrapped = build(source, engine, target / "contracts", botanical_contracts=True)
    a, b = raster(native), raster(wrapped)
    assert len(a) == len(b) and a, (name, engine, "page count changed")
    for index, (old, new) in enumerate(zip(a, b), 1):
        assert old.size == new.size and ImageChops.difference(old, new).getbbox() is None, (
            name, engine, index, "native paint changed")
    old_text, new_text = text(native), text(wrapped)
    assert old_text == new_text, (name, engine, "native searchable text changed")
    logs = list(wrapped.parent.glob("*.pass-*.log" if engine == "lua" else "*.render-*.log"))
    observed = sum(p.read_text(encoding="utf8", errors="replace").count("botanical-contract: validated ") for p in logs)
    if name in {"florilegium", "florilegium-grow", "showcase", "book-demo", "folio-demo"}:
        assert observed > 0, (name, engine, "actual composition wrapper was not invoked")
    print("botanical_enginecheck:", name, engine, len(a), "pixel-exact pages;", observed, "validated observations", flush=True)
    return {"document": name, "engine": engine, "pages": len(a), "observations": observed,
            "text_sha256": hashlib.sha256(new_text).hexdigest(), "pixel_differences": 0}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=2, choices=(1, 2))
    args = parser.parse_args()
    (ROOT / "build").mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="botanical-engine-", dir=ROOT / "build"))
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        checks = list(pool.map(lambda job: compare(folder, *job),
                               [(name, engine) for name in DOCUMENTS for engine in ("lua", "xe")]))
    (folder / "receipt.json").write_text(json.dumps(checks, indent=2) + "\n", encoding="utf8")
    print("botanical_enginecheck:", len(checks), "document/engine pairs; pixels and text exact")
if __name__ == "__main__":
    main()

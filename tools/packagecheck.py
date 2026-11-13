"""Check the source kit by building its own template outside the original tree."""
import hashlib
import re
from pathlib import Path
import subprocess
import tempfile
import zipfile
from package import package, REQUIRED_NOTICES, ROOT


def main():
    archive = package()
    first = hashlib.sha256(archive.read_bytes()).hexdigest()
    assert hashlib.sha256(package().read_bytes()).hexdigest() == first, "Source archive is not reproducible"
    with tempfile.TemporaryDirectory(prefix="florilegium-kit-") as scratch:
        with zipfile.ZipFile(archive) as z:
            z.extractall(scratch)
        kit = Path(scratch) / "florilegium"
        manifest = (kit / "SHA256SUMS").read_text().splitlines()
        checked = set()
        for row in manifest:
            digest, name = row.split("  ", 1)
            assert hashlib.sha256((kit / name).read_bytes()).hexdigest() == digest
            checked.add(name)
        for module, notice in REQUIRED_NOTICES.items():
            if (kit / module).is_file():
                assert notice in checked and (kit / notice).read_bytes() == (ROOT / notice).read_bytes(), (
                    f"Missing or incorrect notice for {module}"
                )
        readme = (kit / "README.md").read_text()
        images = re.findall(r'!\[[^\]]*\]\(([^)]+)\)|<img\b[^>]*\bsrc="([^"]+)"', readme)
        for markdown, html in images:
            path = markdown or html
            if not path.startswith(("https://", "http://")):
                assert (kit / path).is_file(), f"Packaged README image is missing: {path}"
        for engine in ("lua", "xe"):
            result = subprocess.run(["python3", str(kit / "tools/build.py"), str(kit / "examples/book.tex"),
                                     "--engine", engine, "--output-dir", str(kit / "output" / engine)],
                                    cwd=scratch, capture_output=True, text=True)
            (ROOT / "build" / f"kit-{engine}.log").write_text(result.stdout + result.stderr)
            if result.returncode:
                raise AssertionError(f"Extracted source kit failed with {engine}: {result.stdout}{result.stderr}")
            assert (kit / "output" / engine / "book.pdf").is_file()
            bbox = subprocess.check_output(["pdftotext", "-bbox", str(kit / "output" / engine / "book.pdf"), "-"], text=True)
            labels = re.findall(r'<word xMin="([\d.]+)" yMin="([\d.]+)"[^>]*>([0-9ivxlcdm]+)</word>', bbox)
            footers = [(float(x)*2.54/72, float(y)*2.54/72) for x,y,label in labels if float(y)*2.54/72>27.5]
            assert len(footers)>=2 and all(x<7 or x>14 for x,y in footers), "Template retained an ordinary chapter footer"
    print(f"packagecheck: {len(manifest)} file hashes, reproducible archive and extracted Lua/Xe template builds passed")


if __name__ == "__main__":
    main()

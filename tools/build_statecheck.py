"""Fault-inject the actual build driver; this does not substitute for native TeX QA."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch
import build as driver

ROOT = Path(__file__).resolve().parents[1]
PDF = b"%PDF-1.4\n% synthetic driver-control fixture, not a parsed PDF\n%%EOF\n"


class Compiler:
    def __init__(self, source, mode):
        self.source, self.mode, self.calls = source, mode, 0

    def __call__(self, args, **options):
        assert isinstance(args, list) and "-no-shell-escape" in args and not options.get("shell", False)
        self.calls += 1
        folder = Path(options["cwd"])
        name = next(x.split("=", 1)[1] for x in args if x.startswith("-jobname="))
        if self.mode != "missing-pdf":
            (folder / (name + ".pdf")).write_bytes(PDF if self.mode != "partial-pdf" else PDF.removesuffix(b"%%EOF\n"))
        names = [name + ".aux", "chapter-one.aux", name + ".toc", name + ".lof", name + ".lot"]
        for filename in names:
            text = "stable\n"
            if filename == self.mode:
                text = "changing " + str(self.calls) + "\n"
            (folder / filename).write_text(text, encoding="utf8")
        (folder / (name + ".fls")).write_text("INPUT " + str(self.source) + "\n" +
            "".join("OUTPUT " + filename + "\n" for filename in names), encoding="utf8")
        return subprocess.CompletedProcess(args, 0, "synthetic compiler\n", "")


def main():
    (ROOT / "build").mkdir(exist_ok=True)
    results = {}
    with tempfile.TemporaryDirectory(prefix="build-state-", dir=ROOT / "build") as temporary:
        base = Path(temporary).resolve()
        assert base.is_relative_to((ROOT / "build").resolve())
        source = base / "Sources Ω with spaces" / "example book.tex"
        source.parent.mkdir(); source.write_text("Synthetic driver fixture.\n", encoding="utf8")
        for mode in ("stable", "missing-pdf", "partial-pdf", "one-pass", "chapter-one.aux", "case.toc", "case.lof", "case.lot"):
            folder = base / (mode + " Ω output")
            folder.mkdir()
            if mode == "missing-pdf":
                (folder / "case.pdf").write_bytes(PDF)
            compiler = Compiler(source, mode)
            failure = None
            with patch.object(driver.shutil, "which", return_value=sys.executable), \
                 patch.object(driver.subprocess, "check_output", return_value="synthetic compiler 1\n"), \
                 patch.object(driver.subprocess, "run", side_effect=compiler):
                try:
                    driver.build(source, output_dir=folder, job_name="case", max_passes=1 if mode == "one-pass" else 3)
                except RuntimeError as error:
                    failure = str(error)
            receipt = json.loads((folder / "case-build.json").read_text(encoding="utf8"))
            if mode == "stable":
                assert failure is None and receipt["status"] == "complete" and receipt["accepted_pass"] == compiler.calls == 2
                assert receipt['passes'][-1]['compiler_inputs'][str(source)] == driver.file_hash(source), 'UTF-8 filename was silently omitted from input tracking'
            elif mode in {"missing-pdf", "partial-pdf"}:
                assert failure and "missing or incomplete" in failure and receipt["status"] == "failed"
                if mode == "missing-pdf":
                    assert not (folder / "case.pdf").exists(), "old PDF survived the attempted new pass"
            else:
                assert failure and "did not converge" in failure and receipt["status"] == "failed"
                assert compiler.calls == (1 if mode == "one-pass" else 3)
                if mode != "one-pass":
                    assert mode in failure
                    first, last = receipt["passes"][0], receipt["passes"][-1]
                    key = str(folder / "case.aux")
                    assert dict(first["auxiliaries_before_render"])[key] == dict(last["auxiliaries_before_render"])[key]
            results[mode] = {"compiler_calls": compiler.calls, "status": receipt["status"], "diagnostic": failure,
                             "pass_evidence": receipt["passes"]}

        # Check the actual stale-output predicate with unchanged .flo records.
        module_root = base / "renderer"; module_root.mkdir()
        (module_root / "renderer.lua").write_bytes(b"renderer version 1\n")
        folder = base / "external"; folder.mkdir()
        record = folder / "case.flo"; record.write_bytes(b"unchanged document records\n")
        recipe = folder / "source.recipe"; recipe.write_bytes(b"recipe version 1\n")
        font = folder / "source.otf"; font.write_bytes(b"font dependency version 1\n")
        scene = folder / "asset.scene"; scene.write_bytes(b"scene version 1\n")
        image = folder / "asset.pdf"; image.write_bytes(PDF)
        metadata = folder / "case-patterns.tex"; metadata.write_bytes(b"generated metadata\n")
        runtime = {"engine": "synthetic XeTeX"}
        with patch.object(driver, "ROOT", module_root):
            manifest = {"schema_version": 1, "status": "complete", "source_files": driver.source_files(),
                "driver_runtime": runtime, "driver_sha256": driver.file_hash(Path(driver.__file__)),
                "compiler_inputs": {}, "record_sha256": driver.file_hash(record),
                "dependencies": {str(p): driver.file_hash(p) for p in (recipe, font)},
                "outputs": {str(p): driver.file_hash(p) for p in (scene, image, metadata)}, "font_requests": []}
            path = folder / "case-external.json"; path.write_text(json.dumps(manifest), encoding="utf8")
            assert driver.external_state(folder, "case", runtime, {})[0] is not None
            mutations = {}
            for p in (module_root / "renderer.lua", recipe, font, record, scene, image, metadata):
                before = p.read_bytes(); p.write_bytes(before + b"changed\n")
                checked, reason = driver.external_state(folder, "case", runtime, {})
                assert checked is None and reason
                mutations[p.name] = reason
                p.write_bytes(before)
                assert driver.external_state(folder, "case", runtime, {})[0] is not None
            added = module_root / "new-renderer.lua"; added.write_bytes(b"new module\n")
            assert driver.external_state(folder, "case", runtime, {})[0] is None
            results["stale_inputs_and_outputs"] = mutations

    source = {p.relative_to(ROOT).as_posix(): driver.file_hash(p) for p in (Path(__file__), Path(driver.__file__))}
    digest = hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest()
    output = ROOT / "build/build-control" / digest; output.mkdir(parents=True, exist_ok=True)
    receipt = {"schema_version": 1, "source_digest": digest, "source_files": source, "results": results,
               "scope": "Actual driver control flow with a synthetic compiler and explicit byte mutations; native dual-engine QA remains mandatory",
               "native_tex_compiled": False}
    (output / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print("Build control checks passed: fresh complete output, one-pass rejection, chapter/TOC/LOF/LOT churn and eight stale-input/output mutations", digest)


if __name__ == "__main__":
    main()

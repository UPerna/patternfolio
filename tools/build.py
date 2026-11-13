"""Build a florilegium document with LuaLaTeX or XeLaTeX, without shell escape.

python3 tools/build.py book-demo.tex --engine xe --output-dir build/xe
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
AUXILIARY_SUFFIXES = {".aux", ".toc", ".out", ".lof", ".lot", ".nav", ".snm"}


def state(folder, name, engine):
    files = {folder / (name + ext) for ext in AUXILIARY_SUFFIXES}
    if engine == "xe":
        files.add(folder / (name + ".flo"))
    files.add(folder / (name + "-patterns.json"))
    recorder = folder / (name + ".fls")
    if recorder.is_file():
        for line in recorder.read_text(encoding="utf8", errors="replace").splitlines():
            if line.startswith(("OUTPUT ", "INPUT ")):
                path = Path(line.split(" ", 1)[1])
                if not path.is_absolute():
                    path = folder / path
                if path.suffix in AUXILIARY_SUFFIXES:
                    files.add(path.resolve())
    return tuple((str(path), hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None)
                 for path in sorted(files))


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_files():
    return {p.name: file_hash(p) for p in sorted(ROOT.iterdir())
            if p.is_file() and (p.suffix == ".lua" or p.name.startswith("florilegium") and p.suffix in {".sty", ".def"})}


def compiler_inputs(folder, name):
    recorder = folder / (name + ".fls")
    if not recorder.is_file():
        return {}
    paths = set()
    for line in recorder.read_text(encoding="utf8", errors="replace").splitlines():
        if not line.startswith("INPUT "):
            continue
        p = Path(line[6:])
        p = (folder / p).resolve() if not p.is_absolute() else p.resolve()
        # Generated drawings and metadata are checked by the external manifest;
        # auxiliaries have a separate convergence state.
        if p.suffix in AUXILIARY_SUFFIXES or p.name.startswith("florilegium-pattern-"):
            continue
        if p.parent == folder and p.name in {name + "-flo.tex", name + "-flo.pdf", name + "-patterns.tex"}:
            continue
        if p.is_file():
            paths.add(p)
    return {str(p): file_hash(p) for p in sorted(paths)}


def external_state(folder, name, runtime, env):
    """Check actual dependencies and outputs, including damaged scene caches."""
    path = folder / (name + "-external.json")
    if not path.is_file():
        return None, "external manifest missing"
    try:
        manifest = json.loads(path.read_text(encoding="utf8"))
        if manifest.get("schema_version") != 1 or manifest.get("status") != "complete":
            return None, "external manifest incomplete or unsupported"
        if manifest.get("driver_runtime") != runtime or manifest.get("source_files") != source_files():
            return None, "renderer or runtime changed"
        if manifest.get("driver_sha256") != file_hash(Path(__file__)):
            return None, "build driver changed"
        if manifest.get("compiler_inputs") != compiler_inputs(folder, name):
            return None, "compiler input changed"
        if manifest.get("record_sha256") != file_hash(folder / (name + ".flo")):
            return None, "external document records changed"
        for filename, digest in manifest["dependencies"].items():
            dependency = Path(filename)
            dependency = folder / dependency if not dependency.is_absolute() else dependency
            if file_hash(dependency) != digest:
                return None, "renderer, font, recipe or bound input changed: " + filename
        for filename, digest in manifest["outputs"].items():
            p = Path(filename)
            p = folder / p if not p.is_absolute() else p
            if file_hash(p) != digest:
                return None, "generated output is stale or damaged: " + str(p)
        for font in manifest.get("font_requests", []):
            found = None
            for format_name in ("opentype fonts", "truetype fonts"):
                query = subprocess.run(["kpsewhich", "--format=" + format_name, font["name"]],
                                       cwd=folder, env=env, capture_output=True, text=True)
                if query.returncode == 0 and query.stdout.strip():
                    candidate = Path(query.stdout.strip())
                    found = str((folder / candidate if not candidate.is_absolute() else candidate).resolve())
                    break
            expected = Path(font["path"]) if font["path"] else None
            expected = str((folder / expected if not expected.is_absolute() else expected).resolve()) if expected else None
            if found != expected:
                return None, "initial font resolution changed: " + font["name"]
        return manifest, None
    except (OSError, ValueError, KeyError, TypeError) as error:
        return None, "external evidence unavailable: " + str(error)


def changed_files(previous, current):
    old = dict(previous or ())
    new = dict(current)
    return [path for path in sorted(set(old) | set(new)) if old.get(path) != new.get(path)]


def save_build_receipt(folder, name, receipt):
    path = folder / (name + "-build.json")
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    os.replace(temporary, path)


def complete_pdf(path, logfile):
    # A successful compiler exit does not establish that its output is complete.
    # Full parsing/rendering belongs to the integration checks, not this cheap guard.
    if path.is_file():
        with path.open("rb") as file:
            header = file.read(8)
            file.seek(max(0, path.stat().st_size - 1024))
            tail = file.read()
        if header.startswith(b"%PDF-") and tail.rstrip().endswith(b"%%EOF"):
            return
    raise RuntimeError(f"Compiler reported success but its PDF is missing or incomplete: {path}; see {logfile}")


def build(source, engine="lua", output_dir=None, job_name=None, max_passes=6, botanical_contracts=False):
    source = Path(source).resolve()
    if not source.is_file():
        raise ValueError(f"Source not found: {source}")
    if type(max_passes) is not int or not 1 <= max_passes <= 12:
        raise ValueError("max_passes must be an integer from 1 to 12")
    executable = {"lua": "lualatex", "xe": "xelatex"}[engine]
    commands = [executable] + (["texlua", "kpsewhich"] if engine == "xe" else [])
    for command in commands:
        if not shutil.which(command):
            raise RuntimeError(f"{command} is required")
    folder = Path(output_dir or ROOT / "build" / engine).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    name = job_name or re.sub(r"[^A-Za-z0-9_.-]", "_", source.stem)
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", name):
        raise ValueError("Job name must use letters, digits, underscore, hyphen or dot")
    if any(c in source.as_posix() for c in '\\{}%#\n\r"'):
        raise ValueError("Source path contains characters that cannot be passed literally to TeX")
    env = os.environ.copy()
    # Running in the output directory lets xdvipdfmx find generated PDFs, even
    # when that directory contains spaces. Source and installed packages remain
    # available through their normal TeX/Lua search mechanisms.
    env["TEXINPUTS"] = os.pathsep.join([str(source.parent), str(ROOT), env.get("TEXINPUTS", "")])
    env["LUAINPUTS"] = os.pathsep.join([str(ROOT), env.get("LUAINPUTS", "")])
    runtime = {command: {"version": subprocess.check_output([command, "--version"], env=env,
                        encoding="utf8", errors="replace").splitlines()[0],
                        "executable_sha256": file_hash(shutil.which(command))} for command in commands}
    previous = previous_inputs = None
    pdf = folder / (name + ".pdf")
    receipt = {"schema_version": 1, "status": "building", "engine": engine, "source": str(source),
               "job_name": name, "max_passes": max_passes, "runtime": runtime,
               "policy": "Fresh complete PDF; stable complete auxiliary and compiler-input state; verified external dependencies and outputs", "passes": []}
    save_build_receipt(folder, name, receipt)
    try:
        for run in range(1, max_passes + 1):
            evidence = {"pass": run, "rendered": False}
            receipt["passes"].append(evidence)
            before_inputs = compiler_inputs(folder, name)
            manifest, stale = external_state(folder, name, runtime, env) if engine == "xe" else (None, None)
            evidence["external_before"] = stale or "verified"
            pdf.unlink(missing_ok=True)
            if engine == "lua":
                # Lua writes this afresh; a leftover trace cannot certify a new pass.
                (folder / (name + "-patterns.json")).unlink(missing_ok=True)
            prelude = (r"\AtBeginDocument{\directlua{require('pattern_botanical_legacy').install(function(x,d) texio.write_nl('botanical-contract: validated '..d.id) end)}}"
                       if botanical_contracts and engine == "lua" else "")
            if engine == "xe" and manifest is None:
                prelude += r"\expandafter\def\csname flo@externalstale\endcsname{1}"
            command = [executable, "-no-shell-escape", "-halt-on-error", "-interaction=nonstopmode", "-recorder",
                       f"-jobname={name}", prelude + r"\input{" + source.as_posix() + "}"]
            result = subprocess.run(command, cwd=folder, env=env, capture_output=True, encoding="utf8", errors="replace")
            logfile = folder / f"{name}.pass-{run}.log"
            logfile.write_text(result.stdout + result.stderr, encoding="utf8")
            evidence.update(compiler_command=command, compiler_exit=result.returncode, log_sha256=file_hash(logfile))
            if result.returncode:
                tail = "\n".join((result.stdout + result.stderr).splitlines()[-24:])
                raise RuntimeError(f"{executable} failed; see {logfile}\n{tail}")
            complete_pdf(pdf, logfile)
            evidence["pdf_sha256"] = file_hash(pdf)
            current = state(folder, name, engine)
            inputs = compiler_inputs(folder, name)
            evidence["auxiliaries_before_render"] = current
            evidence["changed_auxiliaries"] = changed_files(previous, current)
            evidence["compiler_inputs"] = inputs
            evidence["compiler_inputs_stable_during_pass"] = before_inputs == inputs
            converged = current == previous and inputs == previous_inputs and before_inputs == inputs
            if engine == "xe":
                record = folder / (name + ".flo")
                if not record.is_file():
                    raise RuntimeError("XeLaTeX produced no florilegium records")
                manifest, reason = external_state(folder, name, runtime, env)
                evidence["external_after"] = reason or "verified"
                if manifest is not None and not manifest.get("input_pass_pending", False) and converged:
                    receipt.update(status="complete", final_pdf_sha256=file_hash(pdf), accepted_pass=run)
                    save_build_receipt(folder, name, receipt)
                    return pdf
                if manifest is None:
                    draw_command = ["texlua", str(ROOT / "florilegium-xe.lua"), str(folder / name)]
                    if botanical_contracts:
                        draw_command.append("--botanical-contracts")
                    draw = subprocess.run(draw_command, cwd=folder, env=env, capture_output=True, encoding="utf8", errors="replace")
                    drawlog = folder / f"{name}.render-{run}.log"
                    drawlog.write_text(draw.stdout + draw.stderr, encoding="utf8")
                    evidence.update(rendered=True, render_command=draw_command, render_exit=draw.returncode, render_log_sha256=file_hash(drawlog))
                    if draw.returncode:
                        tail = "\n".join((draw.stdout + draw.stderr).splitlines()[-24:])
                        raise RuntimeError(f"Vector rendering failed; see {drawlog}\n{tail}")
                    path = folder / (name + "-external.json")
                    manifest = json.loads(path.read_text(encoding="utf8"))
                    manifest.update(driver_runtime=runtime, driver_sha256=file_hash(Path(__file__)), compiler_inputs=inputs)
                    temporary = path.with_suffix(".json.tmp")
                    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
                    os.replace(temporary, path)
                    verified, reason = external_state(folder, name, runtime, env)
                    if verified is None:
                        raise RuntimeError("Renderer produced incomplete or stale evidence: " + str(reason))
                    evidence["external_manifest_sha256"] = file_hash(path)
                    current = state(folder, name, engine)
            elif converged:
                receipt.update(status="complete", final_pdf_sha256=file_hash(pdf), accepted_pass=run)
                save_build_receipt(folder, name, receipt)
                return pdf
            evidence["auxiliaries_after_render"] = current
            save_build_receipt(folder, name, receipt)
            previous, previous_inputs = current, inputs
        changed = receipt["passes"][-1].get("changed_auxiliaries", [])
        names = ", ".join(Path(p).name for p in changed) or "compiler inputs or external assets"
        raise RuntimeError(f"Document did not converge in {max_passes} passes; changing: {names}; see {folder}")
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        receipt.update(status="failed", diagnostic=str(error))
        save_build_receipt(folder, name, receipt)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--engine", choices=("lua", "xe"), default="lua")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--job-name")
    parser.add_argument("--max-passes", type=int, default=6, help="bounded convergence limit, 1–12")
    parser.add_argument("--botanical-contracts", action="store_true", help="observe and validate the existing composition through common contracts")
    args = parser.parse_args()
    try:
        print(build(args.source, args.engine, args.output_dir, args.job_name, args.max_passes, botanical_contracts=args.botanical_contracts))
    except (RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()

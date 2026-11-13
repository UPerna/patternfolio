"""Public data-only pattern CLI with owned outputs and resumable batches."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MAX_INPUT = 2 * 1024 * 1024
MAX_ARTIFACT = 32 * 1024 * 1024
VERSION = 1


class CLIError(Exception):
    def __init__(self, message, code=2):
        super().__init__(message)
        self.code = code


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise CLIError(message)


def encode(data):
    return (json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf8")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def decode(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise CLIError(f"Duplicate JSON key {key}")
            result[key] = value
        return result
    def invalid(value):
        raise CLIError(f"Invalid JSON constant {value}")
    try:
        return json.loads(data.decode("utf8"), object_pairs_hook=unique, parse_constant=invalid)
    except (UnicodeError, ValueError) as error:
        raise CLIError(f"Invalid UTF-8 JSON. {error}") from error


def read(path, limit=MAX_INPUT):
    path = Path(path)
    if not path.is_file() or path.stat().st_size > limit:
        raise CLIError(f"Expected a regular file of at most {limit} bytes. {path}")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise CLIError(f"File grew beyond the input limit. {path}")
    return data


def safe_name(name):
    return isinstance(name, str) and re.fullmatch(r"[a-z][a-z0-9-]*\.[a-z]+", name) is not None


def guard_destination(path, allow_source):
    absolute = Path(os.path.abspath(path))
    for part in reversed((absolute, *absolute.parents)):
        try:
            tag = getattr(part.lstat(), "st_reparse_tag", 0)
        except FileNotFoundError:
            tag = 0
        if part.is_symlink() or tag == getattr(stat, "IO_REPARSE_TAG_MOUNT_POINT", 0xA0000003):
            raise CLIError(f"Output paths must have regular directory ancestors. {part}", 4)
    if not allow_source and absolute.resolve().is_relative_to(ROOT):
        raise CLIError("Choose an output directory outside the source tree or explicitly use --allow-source-output.", 4)
    return absolute


def atomic_write(path, data, replace=False):
    """Publish complete bytes on the same filesystem, protecting existing files."""
    descriptor, temporary = tempfile.mkstemp(prefix=".pending-", dir=path.parent)
    temporary = Path(temporary)
    assert temporary.resolve().is_relative_to(path.parent.resolve())
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        if replace:
            os.replace(temporary, path)
        else:
            os.link(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def batch_lock(directory):
    path = directory / ".batch.lock"
    if path.is_symlink():
        raise CLIError("Batch lock must be a regular file.", 4)
    stream = path.open("a+b")
    try:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise CLIError("Batch lock must be a private regular file.", 4)
        stream.seek(0, os.SEEK_END)
        if stream.tell() == 0:
            stream.write(b"0")
            stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise CLIError("Another process owns this batch.", 4) from error
        yield
    finally:
        stream.close()


def source_digest():
    paths = sorted([*ROOT.glob("*.lua"), ROOT / "tools/pattern-driver.lua", Path(__file__)])
    return digest(encode({p.relative_to(ROOT).as_posix(): digest(p.read_bytes()) for p in paths}))


def runtime_digest(args):
    executable = shutil.which(args.lua)
    if executable is None:
        raise CLIError(f"Cannot find the selected runtime. {args.lua}", 70)
    paths = [Path(executable)]
    paths.extend(Path(value) for value in args.lua_arg if Path(value).is_file())
    hashes = {}
    for path in paths:
        with path.open("rb") as stream:
            hashes[str(path.resolve())] = hashlib.file_digest(stream, "sha256").hexdigest()
    return hashes


def bundle_inputs(path):
    path = Path(path)
    manifest = decode(read(path / "result.json"))
    if not isinstance(manifest, dict) or manifest.get("schema_version") != VERSION or manifest.get("status") != "complete":
        raise CLIError("Stored output is incomplete or has an unsupported version.", 3)
    files = {}
    outputs = manifest.get("outputs")
    if not isinstance(outputs, dict) or not outputs:
        raise CLIError("Stored output has no artifact manifest.", 3)
    total = 0
    for name, expected in outputs.items():
        if not safe_name(name):
            raise CLIError("Stored artifact name is invalid.", 3)
        file = path / name
        if file.is_symlink():
            raise CLIError("Stored artifacts must be regular files.", 3)
        data = read(file, MAX_ARTIFACT)
        total += len(data)
        if total > 64 * 1024 * 1024:
            raise CLIError("Stored output exceeds the 64 MiB bundle profile.", 3)
        if digest(data) != expected:
            raise CLIError(f"Stored artifact checksum failed. {name}", 3)
        if name in ("recipe.json", "instance.json", "record.json", "instance-format.json") or name.startswith("block-"):
            if len(data) > MAX_INPUT:
                raise CLIError(f"Stored data exceeds the parser limit. {name}", 3)
            files[name] = data
    if not {"recipe.json", "instance.json", "record.json"} <= files.keys():
        raise CLIError("Stored output is missing recipe, instance or build record.", 3)
    if "instance-format.json" in files:
        info = decode(files["instance-format.json"])
        if info.get("schema") != "legacy-neutral-bundle@1" or info.get("manifest_sha256") != digest(files["instance.json"]):
            raise CLIError("Stored legacy instance manifest is invalid.", 3)
    elif any(name.startswith("block-") for name in files):
        raise CLIError("Stored blocks have no declared instance transport.", 3)
    return files


def prepare(args):
    files = {}
    if args.command in ("replay", "render", "validate-instance"):
        if args.bundle:
            if getattr(args, "instance", None) or getattr(args, "record", None):
                raise CLIError("Use either --from or the three separate stored-data files.")
            files.update(bundle_inputs(args.bundle))
        else:
            if not args.recipe or not args.instance or not args.record:
                raise CLIError("Separate-file replay needs --recipe, --instance and --record.")
            files = {"recipe.json": read(args.recipe), "instance.json": read(args.instance),
                     "record.json": read(args.record)}
    elif args.command == "diagnose":
        files["record.json"] = read(args.record)
    elif args.command in ("generate", "validate"):
        files["recipe.json"] = read(args.recipe)
    names = []
    for item in args.input or []:
        if "=" not in item:
            raise CLIError("Use --input NAME=PATH.")
        name, path = item.split("=", 1)
        if not name or name in names:
            raise CLIError("Dependency names must be nonempty and unique.")
        names.append(name)
        files[f"dependency-{len(names)}.bin"] = read(path, MAX_ARTIFACT)
    request = {"schema_version": VERSION, "command": args.command, "formats": args.format,
               "dependencies": names}
    if getattr(args, "updated_recipe", None):
        if args.command not in ("render", "replay"):
            raise CLIError("An updated recipe requires render or replay.")
        files["previous-recipe.json"] = files["recipe.json"]
        files["recipe.json"] = read(args.updated_recipe)
        request["previous_recipe"] = True
    if getattr(args, "edit_file", None):
        request["edits"] = decode(read(args.edit_file))
    if "instance-format.json" in files:
        request["instance_transport"] = decode(files["instance-format.json"])["schema"]
    if args.command == "schema":
        request["family"] = args.family
    if args.limit:
        recipe = decode(files.get("recipe.json", b"{}"))
        if not isinstance(recipe, dict) or not isinstance(recipe.get("design", {}), dict):
            raise CLIError("Expected a recipe object.")
        declared = recipe.get("design", {}).get("budget")
        if declared is not None and not isinstance(declared, dict):
            raise CLIError("Expected a budget object.")
        limits = dict(declared or
                      {"objects": 10000, "operations": 100000, "bytes": MAX_INPUT})
        for limit in args.limit:
            try:
                name, count = limit.split("=", 1)
                if name not in ("objects", "operations", "bytes") or not re.fullmatch(r"[0-9]+", count):
                    raise ValueError
                limits[name] = int(count)
            except ValueError as error:
                raise CLIError("Use --limit objects=N, operations=N or bytes=N.") from error
        request["limits"] = limits
    identity = digest(encode({"source": source_digest(), "runtime": [args.lua, *args.lua_arg],
                             "runtime_files": runtime_digest(args),
                             "request": request, "inputs": {k: digest(v) for k, v in files.items()}}))
    return request, files, identity


def invoke(args, request, inputs):
    base = Path(tempfile.gettempdir()).resolve()
    with tempfile.TemporaryDirectory(prefix="flo-cli-", dir=base) as temporary:
        job = Path(temporary)
        assert job.resolve().is_relative_to(base)
        (job / "in").mkdir()
        (job / "out").mkdir()
        (job / "request.json").write_bytes(encode(request))
        for name, data in inputs.items():
            assert safe_name(name) or re.fullmatch(r"dependency-[0-9]+\.bin", name)
            (job / "in" / name).write_bytes(data)
        command = [args.lua, *args.lua_arg, str(ROOT / "tools/pattern-driver.lua"), str(job)]
        try:
            process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as error:
            raise CLIError(f"Cannot start the selected Lua runtime. {error}", 70) from error
        try:
            stdout, stderr = process.communicate(timeout=args.timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            process.kill()
            process.communicate()
            code = 130 if isinstance(error, KeyboardInterrupt) else 124
            return {}, {"status": "cancelled", "code": code,
                        "messages": ["Build cancelled." if code == 130 else "Build exceeded its time limit."]}
        outputs = {}
        for path in sorted((job / "out").iterdir()):
            if not safe_name(path.name) or path.is_symlink():
                raise CLIError("Runtime returned an invalid artifact name.", 70)
            outputs[path.name] = read(path, MAX_ARTIFACT)
        diagnostic = decode(outputs.get("diagnostic.json", b"{}"))
        if not isinstance(diagnostic, dict):
            raise CLIError("Runtime returned an invalid diagnostic object.", 70)
        if not diagnostic:
            diagnostic = {"status": "failed", "code": 70,
                          "messages": [(stdout + stderr)[-8192:].decode("utf8", errors="replace")]}
        if process.returncode and diagnostic.get("status") == "complete":
            diagnostic = {"status": "failed", "code": 70, "messages": ["Runtime exited after a partial build."]}
        return outputs, diagnostic


def publish(directory, outputs, diagnostic, identity):
    for name, data in outputs.items():
        atomic_write(directory / name, data)
    manifest = {"schema_version": VERSION, "status": diagnostic["status"], "input_sha256": identity,
                "outputs": {k: digest(v) for k, v in outputs.items()}, "diagnostics": diagnostic}
    if manifest["status"] == "complete" and "record.json" in outputs:
        if decode(outputs["record.json"]).get("status") != "complete":
            raise CLIError("Runtime returned an incomplete build record.", 70)
    atomic_write(directory / "result.json", encode(manifest))
    return manifest


def build(args, directory, prepared):
    directory = guard_destination(directory, args.allow_source_output)
    directory.parent.mkdir(parents=True, exist_ok=True)
    guard_destination(directory, args.allow_source_output)
    try:
        directory.mkdir()
    except FileExistsError as error:
        raise CLIError(f"Output directory already exists. {directory}", 4) from error
    request, files, identity = prepared
    try:
        outputs, diagnostic = invoke(args, request, files)
    except CLIError as error:
        outputs, diagnostic = {}, {"status": "failed", "code": error.code, "messages": [str(error)]}
    return publish(directory, outputs, diagnostic, identity)


def command_code(diagnostic):
    if diagnostic["status"] == "complete":
        return 0
    code = diagnostic.get("code")
    return code if isinstance(code, int) and code in (2, 3, 4, 5, 70, 124, 130) else 3


def batch(args):
    path = Path(args.manifest).resolve()
    data = decode(read(path))
    if not isinstance(data, dict) or set(data) != {"schema_version", "items"} or data["schema_version"] != VERSION:
        raise CLIError("Expected a version 1 batch manifest.")
    items = data["items"]
    if not isinstance(items, list) or not 1 <= len(items) <= 1000:
        raise CLIError("A batch needs 1 to 1000 items.")
    ids = []
    for item in items:
        if not isinstance(item, dict) or set(item) - {"id", "command", "recipe", "bundle", "inputs"}:
            raise CLIError("Invalid batch item fields.")
        name = item.get("id")
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", name) or name in ids:
            raise CLIError("Batch IDs must be unique safe names of at most 64 characters.")
        ids.append(name)
    directory = guard_destination(args.output, args.allow_source_output)
    directory.parent.mkdir(parents=True, exist_ok=True)
    if args.resume:
        if not directory.is_dir():
            raise CLIError("The requested batch does not exist.", 4)
    else:
        try:
            directory.mkdir()
        except FileExistsError as error:
            raise CLIError("Batch output already exists. Use --resume for a saved batch.", 4) from error
    with batch_lock(directory):
        state_file = directory / "batch.json"
        if state_file.is_symlink():
            raise CLIError("Batch state must be a regular file.", 4)
        if args.resume:
            state = decode(read(state_file))
            if not isinstance(state, dict) or state.get("schema_version") != VERSION or state.get("item_ids") != ids:
                raise CLIError("Saved batch IDs differ from the requested batch.", 4)
            if not isinstance(state.get("items"), dict):
                raise CLIError("Saved batch item state is invalid.", 4)
            for name, row in state["items"].items():
                if name not in ids or not isinstance(row, dict) or not isinstance(row.get("attempts"), list):
                    raise CLIError("Saved batch attempt state is invalid.", 4)
        else:
            state = {"schema_version": VERSION, "item_ids": ids, "items": {}}
        def checkpoint():
            payload = encode(state)
            if len(payload) > MAX_INPUT:
                raise CLIError("Batch state exceeds the 2 MiB profile. Start a new batch.", 4)
            atomic_write(state_file, payload, replace=True)
        checkpoint()
        for item in items:
            name = item["id"]
            previous = state["items"].get(name, {})
            entry = {"status": "running", "attempts": previous.get("attempts", [])}
            state["items"][name] = entry
            checkpoint()
            try:
                local = argparse.Namespace(**vars(args))
                local.command = item.get("command", "generate")
                if local.command not in ("generate", "replay"):
                    raise CLIError("Batch commands are generate or replay.")
                key = "recipe" if local.command == "generate" else "bundle"
                if key not in item or not isinstance(item[key], str):
                    raise CLIError(f"Batch item needs {key}.")
                setattr(local, key, path.parent / item[key])
                dependencies = item.get("inputs", {})
                if not isinstance(dependencies, dict) or any(not isinstance(v, str) for v in dependencies.values()):
                    raise CLIError("Batch inputs must map names to filenames.")
                local.input = [f"{k}={path.parent / v}" for k, v in dependencies.items()]
                prepared = prepare(local)
                if previous.get("status") == "complete" and previous.get("input_sha256") == prepared[2]:
                    relative = previous.get("output", "")
                    if not re.fullmatch(re.escape(name) + r"/attempt-[0-9]{4,}", relative):
                        raise CLIError("Saved batch attempt path is invalid.", 4)
                    try:
                        bundle_inputs(directory / relative)
                    except CLIError as error:
                        entry["invalidated"] = str(error)
                    else:
                        state["items"][name] = previous
                        checkpoint()
                        continue
                attempt = len(entry["attempts"]) + 1
                relative = f"{name}/attempt-{attempt:04d}"
                entry.update(input_sha256=prepared[2], output=relative)
                entry["attempts"].append({"output": relative, "input_sha256": prepared[2], "status": "running"})
                checkpoint()
                result = build(local, directory / relative, prepared)
                entry["status"] = result["status"]
                entry["attempts"][-1]["status"] = result["status"]
                entry["diagnostics"] = result["diagnostics"]
                if command_code(result["diagnostics"]) == 130:
                    checkpoint()
                    return {"status": "cancelled", "batch": str(state_file)}, 130
            except CLIError as error:
                entry.update(status="failed", diagnostics={"messages": [str(error)], "code": error.code})
            except OSError as error:
                entry.update(status="failed", diagnostics={"messages": [str(error)], "code": 4})
            except KeyboardInterrupt:
                entry["status"] = "cancelled"
                checkpoint()
                return {"status": "cancelled", "batch": str(state_file)}, 130
            checkpoint()
        failed = sum(row["status"] != "complete" for row in state["items"].values())
        return {"status": "partial" if failed else "complete", "failed_items": failed,
                "total_items": len(items), "batch": str(state_file)}, 5 if failed else 0


def parser():
    p = Parser(description="Generate, validate and replay Florilegium data recipes.")
    p.add_argument("--lua", default="texlua", help="Trusted Lua runtime executable, default texlua.")
    p.add_argument("--lua-arg", action="append", default=[], help="Argument before the managed Lua driver.")
    p.add_argument("--timeout", type=float, default=600, help="Seconds per item, default 600.")
    p.add_argument("--allow-source-output", action="store_true", help="Explicitly allow an output directory inside the source tree.")
    p.set_defaults(input=[], format=None, limit=[])
    commands = p.add_subparsers(dest="command", required=True, parser_class=Parser)
    commands.add_parser("capabilities", help="List registered family IDs and commands.")
    schema = commands.add_parser("schema", help="Inspect a family's real definition.")
    schema.add_argument("family")
    validate = commands.add_parser("validate", help="Validate a data recipe and family input preconditions.")
    validate.add_argument("recipe", type=Path)
    validate.add_argument("--edit-file", type=Path, help="Apply versioned editor intent through the native planner.")
    generate = commands.add_parser("generate", help="Generate and validate an instance, then export its views.")
    generate.add_argument("recipe", type=Path)
    generate.add_argument("--edit-file", type=Path, help="Apply versioned editor intent through the native planner.")
    generate.add_argument("--output", type=Path, required=True)
    for name in ("render", "replay", "validate-instance"):
        command = commands.add_parser(name, help="Validate a stored output and use its cached instance.")
        saved = command.add_mutually_exclusive_group(required=True)
        saved.add_argument("--from", dest="bundle", type=Path)
        saved.add_argument("--recipe", type=Path, help="Recipe for a separately stored instance and build record.")
        command.add_argument("--instance", type=Path)
        command.add_argument("--record", type=Path)
        if name != "validate-instance":
            command.add_argument("--output", type=Path, required=True)
            command.add_argument("--updated-recipe", type=Path, help="Apply style/view changes to the verified stored instance; structural edits are rejected.")
    batches = commands.add_parser("batch", help="Build all items and persist individual outcomes.")
    batches.add_argument("manifest", type=Path)
    batches.add_argument("--output", type=Path, required=True)
    batches.add_argument("--resume", action="store_true")
    diagnostic = commands.add_parser("diagnose", help="Inspect a validated build record.")
    diagnostic.add_argument("record", type=Path)
    for name in ("generate", "render", "replay", "validate-instance", "batch"):
        command = commands.choices[name]
        command.add_argument("--input", action="append", default=[], help="Verified external dependency NAME=PATH.")
        command.add_argument("--limit", action="append", default=[], help="Execution limit objects=N, operations=N or bytes=N.")
        if name != "validate-instance":
            command.add_argument("--format", action="append", choices=("pdf", "svg"), help="Export format. Default both PDF and SVG.")
    return p


def main(argv=None):
    try:
        args = parser().parse_args(argv)
        if args.timeout <= 0 or not args.timeout < float("inf"):
            raise CLIError("Timeout must be finite and positive.")
        args.format = args.format or ["pdf", "svg"]
        if len(args.format) != len(set(args.format)):
            raise CLIError("Export formats must be unique.")
        if args.command == "batch":
            report, code = batch(args)
        else:
            prepared = prepare(args)
            if getattr(args, "output", None):
                result = build(args, args.output, prepared)
                report = {"status": result["status"], "output": str(Path(args.output).absolute()),
                          "input_sha256": result["input_sha256"], "diagnostics": result["diagnostics"]}
                code = command_code(result["diagnostics"])
            else:
                outputs, diagnostic = invoke(args, prepared[0], prepared[1])
                if "report.json" in outputs and diagnostic["status"] == "complete":
                    report = decode(outputs["report.json"])
                else:
                    report = diagnostic
                    if "record.json" in outputs:
                        record = decode(outputs["record.json"])
                        report = {**diagnostic, "validation": record["validation"]}
                code = command_code(diagnostic)
        sys.stdout.buffer.write(encode(report))
        return code
    except CLIError as error:
        sys.stdout.buffer.write(encode({"status": "failed", "code": error.code, "messages": [str(error)]}))
        return error.code
    except KeyboardInterrupt:
        sys.stdout.buffer.write(encode({"status": "cancelled", "code": 130, "messages": ["Command cancelled."]}))
        return 130
    except OSError as error:
        sys.stdout.buffer.write(encode({"status": "failed", "code": 4, "messages": [str(error)]}))
        return 4
    except Exception as error:
        sys.stdout.buffer.write(encode({"status": "failed", "code": 70, "messages": [str(error)]}))
        return 70


if __name__ == "__main__":
    raise SystemExit(main())

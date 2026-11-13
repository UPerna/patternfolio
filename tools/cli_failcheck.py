"""Exercise the public CLI's file ownership, resume and failure boundaries."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]


def audit(lua="texlua",lua_args=()):
    command=[sys.executable,str(ROOT/"tools/pattern.py"),"--lua",lua]
    for value in lua_args:
        command.extend(["--lua-arg",value])
    checks=0
    def run(arguments,expected=0,global_flags=()):
        nonlocal checks
        result=subprocess.run(command+list(global_flags)+list(arguments),cwd=ROOT,capture_output=True,timeout=90)
        assert result.returncode==expected,(arguments,result.returncode,result.stdout[-3000:],result.stderr[-1000:])
        output=json.loads(result.stdout)
        assert isinstance(output,dict)
        checks+=1
        return output
    def read(path):
        return json.loads(path.read_text(encoding="utf8"))
    def write(path,data):
        path.write_text(json.dumps(data,ensure_ascii=False)+"\n",encoding="utf8")
    with tempfile.TemporaryDirectory(prefix="flo-cli-fail-") as temporary:
        base=Path(temporary)
        assert base.resolve().is_relative_to(Path(tempfile.gettempdir()).resolve())
        recipe=base/"periodic Ω input.recipe"
        original=(ROOT/"examples/cli/periodic.recipe").read_bytes()
        recipe.write_bytes(original)
        output=base/"output Ω with spaces"
        run(["generate",str(recipe),"--output",str(output)])
        manifest=read(output/"result.json")
        assert manifest["status"]=="complete"
        direct=base/"separate contract files"
        run(["replay","--recipe",str(output/"recipe.json"),"--instance",str(output/"instance.json"),
             "--record",str(output/"record.json"),"--output",str(direct)])
        assert (direct/"pattern.svg").read_bytes()==(output/"pattern.svg").read_bytes()
        dependency=base/"bytes Ω.bin"
        dependency.write_bytes(b"\x00\xff\r\nverified")
        dependent=read(recipe)
        dependent["dependencies"]["construction"]["external"]={
            "sha256":hashlib.sha256(dependency.read_bytes()).hexdigest()}
        dependency_recipe=base/"dependency.recipe"
        write(dependency_recipe,dependent)
        run(["generate",str(dependency_recipe),"--input",f"external={dependency}",
             "--output",str(base/"verified dependency")])
        dependency.write_bytes(b"modified")
        run(["generate",str(dependency_recipe),"--input",f"external={dependency}",
             "--output",str(base/"modified dependency")],3)
        marker=output/"personal.txt"
        marker.write_text("keep this",encoding="utf8")
        run(["generate",str(recipe),"--output",str(output)],4)
        assert marker.read_text()=="keep this"
        run(["generate",str(recipe),"--output",str(ROOT/"build/forbidden-cli-output")],4)
        duplicate=base/"duplicate.recipe"
        duplicate.write_text('{"kind":"recipe","kind":"recipe"}',encoding="utf8")
        run(["validate",str(duplicate)],3)
        hostile=base/"code.recipe"
        sentinel=base/"executed.txt"
        hostile.write_text('local f=io.open('+json.dumps(str(sentinel).replace("\\","/"))+',"w");f:write("executed")',encoding="utf8")
        run(["validate",str(hostile)],3)
        assert not sentinel.exists()
        run(["generate",str(recipe),"--output",str(base/"limited"),"--limit","operations=0"],3)
        assert read(base/"limited/record.json")["outputs"]==[]
        run(["generate",str(recipe),"--output",str(base/"timeout")],124,["--timeout","0.001"])
        assert read(base/"timeout/result.json")["status"]=="cancelled"
        broken=base/"bad.recipe"
        broken.write_text("{}",encoding="utf8")
        batch_file=base/"mixed Ω.json"
        write(batch_file,{"schema_version":1,"items":[
            {"id":"good","recipe":recipe.name},{"id":"bad","recipe":broken.name}]})
        batch=base/"mixed batch"
        run(["batch",str(batch_file),"--output",str(batch)],5)
        state=read(batch/"batch.json")
        assert state["items"]["good"]["status"]=="complete" and state["items"]["bad"]["status"]=="failed"
        saved=state["items"]["good"]["output"]
        run(["batch",str(batch_file),"--output",str(batch),"--resume"],5)
        assert read(batch/"batch.json")["items"]["good"]["output"]==saved
        broken.write_bytes(original)
        run(["batch",str(batch_file),"--output",str(batch),"--resume"])
        state=read(batch/"batch.json")
        assert len(state["items"]["good"]["attempts"])==1 and len(state["items"]["bad"]["attempts"])==3
        damaged=batch/state["items"]["good"]["output"]/"pattern.svg"
        damaged.write_bytes(damaged.read_bytes()+b" ")
        run(["batch",str(batch_file),"--output",str(batch),"--resume"])
        repaired=read(batch/"batch.json")
        assert len(repaired["items"]["good"]["attempts"])==2
        assert damaged.read_bytes().endswith(b" ")
        write(batch_file,{"schema_version":1,"items":[{"id":"../escape","recipe":recipe.name}]})
        run(["batch",str(batch_file),"--output",str(base/"bad ids")],2)
        write(batch_file,{"schema_version":1,"items":[
            {"id":"good","recipe":recipe.name},{"id":"bad","recipe":broken.name}]})
        spec=importlib.util.spec_from_file_location("tested_pattern_cli",ROOT/"tools/pattern.py")
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with module.batch_lock(batch):
            run(["batch",str(batch_file),"--output",str(batch),"--resume"],4)
        outside=base/"outside"
        outside.mkdir()
        linked=base/"linked output"
        symlink_checked=False
        try:
            linked.symlink_to(outside,target_is_directory=True)
        except OSError:
            pass
        else:
            run(["generate",str(recipe),"--output",str(linked/"child")],4)
            assert not (outside/"child").exists()
            symlink_checked=True
        junction_checked=False
        if os.name=="nt":
            junction=Path(os.environ.get("SystemDrive","C:")+"/")/"Documents and Settings"
            try:
                tag=getattr(junction.lstat(),"st_reparse_tag",0)
            except OSError:
                tag=0
            if tag==getattr(stat,"IO_REPARSE_TAG_MOUNT_POINT",0xA0000003):
                result=run(["generate",str(recipe),"--output",str(junction/"Florilegium CLI guard test")],4)
                assert "regular directory ancestors" in " ".join(result["messages"])
                junction_checked=True
        external=base/"external empty file"
        external.write_bytes(b"")
        hardlinks=base/"hardlink batch"
        hardlinks.mkdir()
        os.link(external,hardlinks/".batch.lock")
        try:
            with module.batch_lock(hardlinks):
                raise AssertionError("Hardlinked lock was accepted")
        except module.CLIError:
            checks+=1
        assert external.read_bytes()==b""
        concurrent=base/"concurrent"
        args=command+["generate",str(recipe),"--output",str(concurrent)]
        processes=[subprocess.Popen(args,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for _ in range(2)]
        returns=[]
        for process in processes:
            stdout,stderr=process.communicate(timeout=90)
            assert isinstance(json.loads(stdout),dict),(stdout,stderr)
            returns.append(process.returncode)
        assert sorted(returns)==[0,4],returns
        checks+=1
        interrupted=base/"interrupted"
        process=subprocess.Popen(command+["generate",str(recipe),"--output",str(interrupted)],
                                 cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        cancellation_checked=False
        if os.name!="nt":
            deadline=time.monotonic()+15
            while not interrupted.exists() and process.poll() is None and time.monotonic()<deadline:
                time.sleep(.01)
            assert process.poll() is None
            process.send_signal(signal.SIGINT)
            stdout,stderr=process.communicate(timeout=15)
            assert process.returncode==130,(stdout,stderr)
            assert json.loads(stdout)["status"]=="cancelled"
            assert not (interrupted/"result.json").exists() or read(interrupted/"result.json")["status"]!="complete"
            cancellation_checked=True
            checks+=1
        else:
            process.communicate(timeout=90)
            assert process.returncode==0
        result={"checks":checks,"symlink_checked":symlink_checked,"signal_cancellation_checked":cancellation_checked,
                "junction_checked":junction_checked,
                "timeout_checked":True,"hardlink_lock_checked":True,"partial_batch_repaired":True,
                "damaged_output_rebuilt":True,"unicode_paths_checked":True,"concurrent_destination_checked":True}
    return result


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--lua",default="texlua")
    parser.add_argument("--lua-arg",action="append",default=[])
    args=parser.parse_args()
    print(json.dumps(audit(args.lua,args.lua_arg),sort_keys=True))

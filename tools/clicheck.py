"""Build and replay every public family through the actual command-line entrypoint."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from cli_failcheck import audit as failure_audit

ROOT=Path(__file__).resolve().parents[1]


def fingerprint():
    paths=[*ROOT.glob("*.lua"),*ROOT.glob("examples/cli/*.recipe"),*ROOT.glob("examples/cli/*.json")]
    paths.extend(ROOT/"tools"/name for name in ("pattern.py","pattern-driver.lua","clicheck.py","cli_failcheck.py"))
    manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
    return hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--lua",default="texlua")
    parser.add_argument("--lua-arg",action="append",default=[])
    parser.add_argument("--timeout",type=int,default=600)
    parser.add_argument("--local-pdf-reader",action="store_true")
    args=parser.parse_args()
    source=fingerprint()
    destination=ROOT/"build/cli"/source
    destination.mkdir(parents=True,exist_ok=True)
    command=[sys.executable,str(ROOT/"tools/pattern.py"),"--lua",args.lua,"--timeout",str(args.timeout)]
    for value in args.lua_arg:
        command.extend(["--lua-arg",value])
    counts=collections.Counter()
    def run(arguments,timeout=None):
        result=subprocess.run(command+arguments,cwd=ROOT,capture_output=True,
                              timeout=timeout or args.timeout+30)
        assert result.returncode==0,(arguments,result.returncode,result.stdout[-4000:],result.stderr[-1000:])
        data=json.loads(result.stdout)
        counts[arguments[0]]+=1
        return data
    def read(path):
        return json.loads(path.read_text(encoding="utf8"))
    catalog=read(ROOT/"examples/cli/catalog.json")["examples"]
    capabilities=run(["capabilities"])
    assert set(capabilities["families"])=={x["family"] for x in catalog}
    assert len(catalog)==22
    for row in catalog:
        recipe=ROOT/"examples/cli"/row["recipe"]
        assert hashlib.sha256(recipe.read_bytes()).hexdigest()==row["sha256"]
        assert run(["schema",row["family"]])["definition"]["id"]==row["family"]
        assert run(["validate",str(recipe)])["family"]==row["family"]
    results={}
    with tempfile.TemporaryDirectory(prefix="flo-cli-consumer-") as temporary:
        base=Path(temporary)
        assert base.resolve().is_relative_to(Path(tempfile.gettempdir()).resolve())
        generated=base/"generated Ω families"
        report=run(["batch",str(ROOT/"examples/cli/all-families.json"),"--output",str(generated)],
                   timeout=len(catalog)*(args.timeout+5))
        assert report["status"]=="complete" and report["failed_items"]==0
        state=read(generated/"batch.json")
        assert len(state["items"])==22
        source_digests=set()
        for row in catalog:
            entry=state["items"][row["id"]]
            assert entry["status"]=="complete"
            bundle=generated/entry["output"]
            record=read(bundle/"record.json")
            assert record["status"]=="complete" and record["validation"]["status"]=="passed"
            source_digests.add(record["source"]["digest"])
            validate=run(["validate-instance","--from",str(bundle)])
            assert validate["status"]=="complete" and validate["validation"]["status"]=="passed"
            replayed=base/"replayed Ω families"/row["id"]
            assert run(["replay","--from",str(bundle),"--output",str(replayed)])["status"]=="complete"
            replay=read(replayed/"record.json")
            assert replay["lineage"][0]["role"]=="validated-instance-replay"
            assert replay["lineage"][0]["parent_ref"]==record["id"]
            hashes={}
            for name in ("instance.json","pattern.pdf","pattern.svg"):
                a,b=(bundle/name).read_bytes(),(replayed/name).read_bytes()
                assert a==b,(row["id"],name,"cached replay changed output")
                hashes[name]=hashlib.sha256(a).hexdigest()
            pdf=bundle/"pattern.pdf"
            assert pdf.read_bytes().startswith(b"%PDF-") and pdf.read_bytes().rstrip().endswith(b"%%EOF")
            svg=ET.parse(bundle/"pattern.svg").getroot()
            assert svg.tag=="{http://www.w3.org/2000/svg}svg"
            assert not list(svg.iter("{http://www.w3.org/2000/svg}image"))
            view=read(bundle/"view.json")
            bounds=view["crop"]
            if args.local_pdf_reader:
                from pypdf import PdfReader
                pages=PdfReader(pdf).pages
                assert len(pages)==1
                width,height=float(pages[0].mediabox.width),float(pages[0].mediabox.height)
            else:
                info=subprocess.check_output(["pdfinfo",str(pdf)]).decode()
                match=re.search(r"Page size:\s+([0-9.]+) x ([0-9.]+)",info)
                assert match
                width,height=float(match[1]),float(match[2])
            assert abs(width*2.54/72-(bounds[2]-bounds[0]))<.002
            assert abs(height*2.54/72-(bounds[3]-bounds[1]))<.002
            if row["id"]=="micrography":
                instance=read(bundle/"instance.json")
                text=instance["structures"]["text"]
                runs={r["id"]:r["text"] for r in text["runs"]}
                expected="".join(runs[key] for key in text["reading_order"])
                if args.local_pdf_reader:
                    extracted="".join(page.extract_text() for page in pages)
                else:
                    extracted=subprocess.check_output(["pdftotext","-raw",str(pdf),"-"]).decode("utf8")
                assert extracted.split()==expected.split(),"CLI micrography lost searchable text"
            for suffix in ("pdf","svg"):
                shutil.copyfile(bundle/("pattern."+suffix),destination/(row["id"]+"."+suffix))
            if row["id"] in ("micrography","decobrush"):
                numerical=destination/"numerical"/row["id"]
                numerical.mkdir(parents=True,exist_ok=True)
                for name in ("instance.json","pattern.pdf","pattern.svg"):
                    shutil.copyfile(bundle/name,numerical/name)
            if row["id"]=="escher":
                cache=destination/"solver-cache"
                if cache.exists():
                    assert all((cache/p.name).read_bytes()==p.read_bytes() for p in bundle.iterdir())
                else:
                    # Export readable evidence without retaining private job-file modes.
                    shutil.copytree(bundle,cache,copy_function=shutil.copyfile)
                if sys.platform!="win32":
                    assert all(p.stat().st_mode&0o444==0o444 for p in cache.iterdir()),"Unreadable exported cache evidence"
            results[row["id"]]={"family":row["family"],"artifacts":hashes,
                                "parent_record":record["id"],"replay_record":replay["id"],
                                "source_digest":record["source"]["digest"]}
            print("CLI family accepted",row["id"],flush=True)
        assert len(source_digests)==1,"Source changed during the all-family build"
        first=generated/state["items"]["periodic"]["output"]
        rendered=base/"render command"
        run(["render","--from",str(first),"--output",str(rendered)])
        assert (rendered/"pattern.svg").read_bytes()==(first/"pattern.svg").read_bytes()
        assert run(["diagnose",str(first/"record.json")])["status"]=="complete"
        direct=base/"standalone contract files"
        run(["replay","--recipe",str(first/"recipe.json"),"--instance",str(first/"instance.json"),
             "--record",str(first/"record.json"),"--output",str(direct)])
        assert (direct/"pattern.svg").read_bytes()==(first/"pattern.svg").read_bytes()
    failures=failure_audit(args.lua,args.lua_arg)
    if sys.platform!="win32":
        assert failures["symlink_checked"] and failures["signal_cancellation_checked"]
    assert fingerprint()==source,"Source changed during CLI acceptance"
    receipt={"schema_version":1,"source_digest":source,"families":results,"public_commands":dict(counts),
             "pdf_reader":"pypdf local QA" if args.local_pdf_reader else "Poppler pdfinfo and pdftotext -raw",
             "failures":failures,"cached_optimizer_replay":"Generator bypass plus unchanged Escher solver witness and output"}
    (destination/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf8")
    print("CLI consumer acceptance",len(results),"families",failures["checks"],"failure checks")


if __name__=="__main__":
    main()

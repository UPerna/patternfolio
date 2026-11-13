"""Fast checks for the actual release source, lock and required coverage."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
READ=lambda p:json.loads(p.read_text(encoding='utf8'))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-revision')
    parser.add_argument('--output',type=Path,default=ROOT/'build/release-admission.json')
    a=parser.parse_args()
    git=['git','-c','safe.directory='+ROOT.as_posix(),'-C',str(ROOT)]
    revision=subprocess.check_output(git+['rev-parse','HEAD']).decode().strip()
    tree=subprocess.check_output(git+['rev-parse','HEAD^{tree}']).decode().strip()
    if a.expected_revision:
        assert revision==a.expected_revision,'Checkout is not the requested source revision'
        assert not subprocess.check_output(git+['status','--porcelain','--untracked-files=no'])
    lock=READ(ROOT/'DEPENDENCIES.lock.json');assert lock['schema_version']==1
    for name,digest in lock['vendored_sha256'].items():assert SHA(ROOT/name)==digest,name
    flow=ROOT/'.github/workflows/build.yml';yaml=flow.read_text(encoding='utf8')
    uses=re.findall(r'\buses:\s+([A-Za-z0-9_/-]+)@([a-f0-9]+)',yaml)
    assert len(uses)==len(re.findall(r'\buses:',yaml)) and {name for name,sha in uses}==set(lock['actions'])
    assert all(sha==lock['actions'][name]['sha'] and len(sha)==40 for name,sha in uses)
    assert yaml.count('persist-credentials: false')==sum(name=='actions/checkout'for name,sha in uses)
    assert yaml.count('docker_image: '+lock['native_ci_image']['reference'])==sum(name=='xu-cheng/latex-action'for name,sha in uses)
    assert 'permissions:\n  contents: read' in yaml and not re.search(r'^\s*permissions:\s*write-all|^\s*\w+:\s*write\s*$',yaml,re.M)
    assert re.search(r"node-version:\s*['\"]?"+re.escape(lock['node']['version'])+r"['\"]?\s*$",yaml,re.M)
    assert 'playwright@'+lock['requirements']['browser_qa']['playwright'] in yaml
    assert 'pypdf=='+lock['requirements']['browser_qa']['pypdf'] in yaml
    profiles=READ(ROOT/'examples/cli/catalog.json')['examples'];assert len(profiles)==22
    for row in profiles:assert SHA(ROOT/'examples/cli'/row['recipe'])==row['sha256']
    with (ROOT/'docs/research/COVERAGE.csv').open(encoding='utf8',newline='')as f:ledger=list(csv.DictReader(f))
    mandatory=[x for x in ledger if x['priority']=='mandatory'];assert len(mandatory)==46
    for row in mandatory:
        assert row['status']=='passed' and row['evidence']
        for ref in row['evidence'].split(';'):
            path=(ROOT/ref.strip()).resolve();assert path.is_relative_to(ROOT) and path.is_file()
    result={'status':'passed','revision':revision,'tree':tree,'exact_checkout_guard':bool(a.expected_revision),
            'workflow_sha256':SHA(flow),'lock_sha256':SHA(ROOT/'DEPENDENCIES.lock.json'),'locked_action_uses':len(uses),
            'verified_vendor_hashes':len(lock['vendored_sha256']),'recipe_profiles':22,'mandatory_evidence_rows':46,
            'scope':'Fast source and metadata checks. Native/browser/runtime/packaging gates are separate and remain required.'}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n',encoding='utf8');print(json.dumps(result,sort_keys=True))


if __name__=='__main__':main()

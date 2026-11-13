"""Verify the review-candidate transport and select its actual browser files for CI."""
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import zipfile

SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
READ=lambda p:json.loads(p.read_text(encoding='utf8'))


def bind_browser(root, release, clean_receipt, canonical, destination, proof_path):
    release=release.resolve();destination=destination.resolve()
    def git(expression):
        return subprocess.check_output(['git','-c','safe.directory='+root.as_posix(),'-C',str(root),'rev-parse',expression]).decode().strip()
    revision,tree=git('HEAD'),git('HEAD^{tree}')
    receipt=READ(release/'release.json');clean=READ(clean_receipt)
    assert receipt['kind']=='review-candidate' and receipt['revision']==clean['revision']==revision
    assert receipt['tree']==clean['tree']==tree and clean['status']=='passed'
    assert clean['source_only_reassembly_byte_equal'] and clean['all_family_cli_profiles']==22 and clean['native_dual_engines']==2
    components=receipt['components'];assert set(components)=={'source','browser','atlas'}
    exact={'release.json','florilegium-source.zip','florilegium-browser.zip','florilegium-atlas.zip'}
    manifest={}
    for line in (release/'SHA256SUMS').read_text(encoding='utf8').splitlines():
        digest,name=line.split('  ',1);assert name in exact and name not in manifest
        assert SHA(release/name)==digest;manifest[name]=digest
    assert set(manifest)==exact
    assert set(p.name for p in release.iterdir())==exact|{'SHA256SUMS'}
    for name,record in components.items():
        assert record['filename']=='florilegium-'+name+'.zip'
        path=release/record['filename'];assert SHA(path)==record['sha256'] and path.stat().st_size==record['bytes']
    assert components['source']['sha256']==clean['source_zip']['sha256']
    assert receipt['source_manifest_sha256']==clean['source_manifest_sha256']
    assert canonical==clean['browser_assets']
    destination.mkdir(parents=True,exist_ok=False)
    with zipfile.ZipFile(release/'florilegium-browser.zip')as z:
        names={};prefix='florilegium-browser/'
        for item in z.infolist():
            assert item.filename.startswith(prefix) and not item.is_dir() and not stat.S_ISLNK(item.external_attr>>16)
            name=item.filename[len(prefix):];target=(destination/name).resolve()
            assert name and target.is_relative_to(destination) and name not in names
            names[name]=item
        declared={}
        for line in z.read(names['SHA256SUMS']).decode('utf8').splitlines():
            digest,name=line.split('  ',1);assert name in names and name not in declared
            assert hashlib.sha256(z.read(names[name])).hexdigest()==digest;declared[name]=digest
        notices={'notices/MIT.txt','notices/WASMOON-LICENSE.txt','notices/LUA-LICENSE.txt','notices/HASH-WASM-LICENSE.txt'}
        assert set(names)==set(declared)|{'SHA256SUMS'}
        assert set(declared)==set(canonical)|notices
        for name,digest in canonical.items():assert declared[name]==digest,name
        for name,item in names.items():
            path=destination/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(z.read(item))
    result={'schema_version':1,'status':'release_browser_bound_for_actual_suite','revision':revision,'tree':tree,
            'component_hashes':{k:v['sha256']for k,v in components.items()},
            'source_clean_receipt_sha256':SHA(clean_receipt),'release_manifest_sha256':SHA(release/'release.json'),
            'browser_assets_exact':canonical,'browser_archive_files_verified':len(names),
            'browser_origin_scope':'The existing real browser parity/editor/performance suite serves this extracted release component.'}
    proof_path.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n',encoding='utf8')
    return destination

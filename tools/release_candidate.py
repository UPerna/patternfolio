"""Assemble deterministic, source-bound candidate components without publishing."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
HASH = lambda b: hashlib.sha256(b).hexdigest()
JSON = lambda x: (json.dumps(x, sort_keys=True, ensure_ascii=False, indent=2)+'\n').encode('utf8')


def git(root, *args, data=None):
    result = subprocess.run(['git','-c','safe.directory='+root.as_posix(),'-c','core.autocrlf=false','-C',str(root),*args],
                            input=data, capture_output=True, check=True)
    return result.stdout


def safe(root, name):
    path = root/name
    assert path.resolve().is_relative_to(root.resolve()) and not path.is_symlink(), name
    return path


def source_snapshot(root):
    # The release includes exactly the legacy kit's declared source selection,
    # plus the workflow, attributes and dependency record required for this RC.
    manifest = root/'SOURCE.json'
    if manifest.is_file() and not (root/'.git').exists():
        source = json.loads(manifest.read_text(encoding='utf8'))
        files = {}
        for name, item in source['files'].items():
            data = safe(root,name).read_bytes()
            assert HASH(data) == item['sha256']
            files[name] = (data, item['mode'])
        return source, files
    revision = git(root,'rev-parse','HEAD').decode().strip()
    tree = git(root,'rev-parse','HEAD^{tree}').decode().strip()
    subprocess.run([sys.executable,str(root/'tools/package.py')],cwd=root,check=True,capture_output=True,timeout=180)
    with zipfile.ZipFile(root/'build/florilegium-v1.4-source.zip') as z:
        names = {line.split('  ',1)[1] for line in z.read('florilegium/SHA256SUMS').decode().splitlines()}
    names.update({'.gitattributes','.gitignore','.github/workflows/build.yml'})
    if (root/'DEPENDENCIES.lock.json').is_file():names.add('DEPENDENCIES.lock.json')
    entries = {}
    for item in git(root,'ls-tree','-r','-z',revision).split(b'\0'):
        if not item:continue
        meta,name = item.split(b'\t',1);mode,kind,oid = meta.decode().split()
        if name.decode() in names:
            assert kind=='blob' and mode in ('100644','100755')
            entries[name.decode()] = mode,oid
    assert set(entries)==names, ('Release selection must be committed',sorted(names-set(entries)))
    ids = sorted({v[1] for v in entries.values()})
    raw = git(root,'cat-file','--batch',data=('\n'.join(ids)+'\n').encode());at=0;blobs={}
    for oid in ids:
        end=raw.index(b'\n',at);actual,kind,length=raw[at:end].decode().split();assert actual==oid and kind=='blob'
        at=end+1;data=raw[at:at+int(length)];at+=int(length);assert raw[at:at+1]==b'\n';at+=1
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==oid
        blobs[oid]=data
    assert at==len(raw)
    files={name:(blobs[oid],mode) for name,(mode,oid) in entries.items()}
    source={'schema_version':1,'revision':revision,'tree':tree,'selection':'Canonical Git bytes of the declared compact source kit plus release infrastructure.',
            'files':{name:{'sha256':HASH(data),'mode':mode} for name,(data,mode) in sorted(files.items())}}
    return source,files


def archive(path, prefix, files):
    # Input modes come from Git or the verified source manifest, not host umask.
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,(data,mode) in sorted(files.items()):
            entry=zipfile.ZipInfo(prefix+'/'+name,(1980,1,1,0,0,0));entry.create_system=3
            entry.external_attr=(stat.S_IFREG|int(mode,8)&0o777)<<16;entry.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(entry,data,compresslevel=9)
    with zipfile.ZipFile(path) as z:
        assert {x.filename for x in z.infolist()}=={prefix+'/'+n for n in files}
        for name,(data,mode) in files.items():
            entry=z.getinfo(prefix+'/'+name);assert z.read(entry)==data
            assert stat.S_IMODE(entry.external_attr>>16)==int(mode,8)&0o777
    return {'filename':path.name,'sha256':HASH(path.read_bytes()),'bytes':path.stat().st_size,'files':len(files)}


def checksums(files):
    return ''.join(HASH(data)+'  '+name+'\n' for name,(data,_) in sorted(files.items())).encode()


def extract(source_zip, destination):
    with zipfile.ZipFile(source_zip) as z:
        names=set()
        for item in z.infolist():
            target=safe(destination,item.filename);assert target not in names;names.add(target)
            assert not stat.S_ISLNK(item.external_attr>>16)
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(z.read(item))
            if os.name!='nt':target.chmod(stat.S_IMODE(item.external_attr>>16))
    return destination/'florilegium'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=ROOT)
    ap.add_argument('--output',type=Path,default=ROOT/'build/release-candidate')
    ap.add_argument('--atlas',type=Path)
    ap.add_argument('--source-only',action='store_true')
    ap.add_argument('--verify-repeat',action='store_true',help='Reassemble independently and compare complete candidate bytes')
    a=ap.parse_args();root=a.root.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    source,files=source_snapshot(root);source_data=JSON(source)
    files['SOURCE.json']=(source_data,'100644');files['SHA256SUMS']=(checksums(files),'100644')
    components={'source':archive(out/'florilegium-source.zip','florilegium',files)}
    if not a.source_only:
        with tempfile.TemporaryDirectory(prefix='florilegium clean browser ',dir=out.parent) as temporary:
            kit=extract(out/'florilegium-source.zip',Path(temporary))
            subprocess.run([sys.executable,'tools/webpackage.py'],cwd=kit,check=True,capture_output=True,timeout=180)
            web=kit/'build/web'
            browser={p.relative_to(web).as_posix():(p.read_bytes(),'100644')for p in sorted(web.rglob('*'))if p.is_file()}
            for name,path in {'MIT.txt':'LICENSE','WASMOON-LICENSE.txt':'web/vendor/wasmoon-1.16.0/LICENSE',
                              'LUA-LICENSE.txt':'web/vendor/wasmoon-1.16.0/LUA-LICENSE.txt',
                              'HASH-WASM-LICENSE.txt':'web/vendor/hash-wasm-4.12.0/LICENSE'}.items():
                browser['notices/'+name]=(safe(kit,path).read_bytes(),'100644')
            browser['SHA256SUMS']=(checksums(browser),'100644')
            components['browser']=archive(out/'florilegium-browser.zip','florilegium-browser',browser)
        assert a.atlas is not None,'A verified generated atlas is required for the complete candidate'
        atlas=a.atlas.resolve();metadata=json.loads((atlas/'gallery.json').read_text(encoding='utf8'))
        assert metadata['status']=='passed' and len(metadata['profiles'])==22
        for name,sha in metadata['sources'].items():assert HASH(files[name][0])==sha,(name,'Atlas uses another source')
        atlas_files={p.relative_to(atlas).as_posix():(p.read_bytes(),'100644')for p in sorted(atlas.rglob('*'))if p.is_file()}
        declared={}
        for line in (atlas/'SHA256SUMS').read_text(encoding='utf8').splitlines():
            sha,name=line.split('  ',1);assert name not in declared and HASH(atlas_files[name][0])==sha;declared[name]=sha
        assert set(declared)==set(atlas_files)-{'SHA256SUMS'}
        components['atlas']=archive(out/'florilegium-atlas.zip','pattern-atlas',atlas_files)
    release={'schema_version':1,'kind':'review-candidate','revision':source['revision'],'tree':source['tree'],
             'source_manifest_sha256':HASH(source_data),'components':components,
             'archive_runtime':{'python':platform.python_version(),'zlib':zlib.ZLIB_RUNTIME_VERSION},
             'reproducibility':'Repeated fixed-source component ZIPs are byte-identical in the same Python/zlib archive profile, with sorted members, Git modes and fixed timestamps. Extracted source bytes and modes are canonical across hosts. Native vectors retain the named comparison policies.',
             'publication':'Reviewable branch/workflow artifacts only; no merge, production deployment or public release tag.'}
    (out/'release.json').write_bytes(JSON(release))
    hashes={p.name:(p.read_bytes(),'100644')for p in out.iterdir()if p.is_file()}
    (out/'SHA256SUMS').write_bytes(checksums(hashes))
    if a.verify_repeat:
        with tempfile.TemporaryDirectory(prefix='release repeat ',dir=out.parent) as temporary:
            second=Path(temporary)/'candidate'
            command=[sys.executable,__file__,'--root',str(root),'--output',str(second)]
            if a.source_only:command.append('--source-only')
            else:command.extend(['--atlas',str(a.atlas.resolve())])
            subprocess.run(command,cwd=root,check=True,capture_output=True,timeout=600)
            names={p.name for p in out.iterdir() if p.is_file()}
            assert names=={p.name for p in second.iterdir() if p.is_file()}
            identical={name:HASH((out/name).read_bytes()) for name in sorted(names)}
            assert identical=={name:HASH((second/name).read_bytes()) for name in sorted(names)}
            proof={'status':'passed','revision':source['revision'],'tree':source['tree'],
                   'separate_assembly_process':True,'archive_runtime':release['archive_runtime'],
                   'byte_identical':identical}
            (out.parent/'release-reproducibility.json').write_bytes(JSON(proof))
    print(json.dumps(release,sort_keys=True))


if __name__=='__main__':main()

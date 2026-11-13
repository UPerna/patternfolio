"""Build a self-contained browser source bundle; no runtime CDN or package install."""
import base64,hashlib,json,pathlib,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
def package(destination=None):
    out=pathlib.Path(destination or ROOT/'build/web');out.mkdir(parents=True,exist_ok=True)
    for name in ('index.html','runtime.html','editor.js','editor.css','client.js','worker.js','cache.js'):
        shutil.copyfile(ROOT/'web'/name,out/name)
    vendor=ROOT/'web/vendor/wasmoon-1.16.0'
    runtime_manifest=json.loads((ROOT/'web/vendor/manifest.json').read_text(encoding='utf8'))
    hash_vendor=ROOT/'web/vendor/hash-wasm-4.12.0'
    hash_manifest=json.loads((ROOT/'web/vendor/hash-manifest.json').read_text(encoding='utf8'))
    assert hash_manifest['version']=='4.12.0'
    for name,digest in hash_manifest['files'].items():
        assert hashlib.sha256((hash_vendor/name).read_bytes()).hexdigest()==digest, 'Pinned SHA asset differs: '+name
    shutil.copyfile(hash_vendor/'sha256.js',out/'sha256.js')
    assert runtime_manifest['version']=='1.16.0'
    for name,digest in runtime_manifest['files'].items():
        path=vendor/name
        assert not path.is_symlink()and hashlib.sha256(path.read_bytes()).hexdigest()==digest, 'Pinned runtime asset differs: '+name
    shutil.copyfile(vendor/'index.js',out/'wasmoon.js')
    wasm=base64.b64decode((vendor/'glue.wasm.base64').read_bytes(),validate=True)
    assert hashlib.sha256(wasm).hexdigest()==runtime_manifest['raw_wasm_sha256']
    (out/'runtime.wasm').write_bytes(wasm)
    source={p.name:p.read_bytes().decode('utf8')for p in sorted(ROOT.glob('*.lua'))}
    examples={p.name:p.read_bytes().decode('utf8')for p in sorted((ROOT/'examples/cli').iterdir())if p.suffix in('.recipe','.json')}
    bridge_files={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest()for name in
                  ('web/client.js','web/worker.js','web/cache.js','web/editor.js','web/editor.css','web/index.html','web/runtime.html','tools/webpackage.py','web/vendor/manifest.json','web/vendor/hash-manifest.json')}
    bridge_digest=hashlib.sha256(json.dumps(bridge_files,sort_keys=True).encode()).hexdigest()
    bundle={'schema_version':1,'source':source,'examples':examples,'bridge_files':bridge_files,
            'runtime':'wasmoon-1.16.0/lua54/browser-v1/hash-wasm-4.12.0/'+bridge_digest}
    (out/'bundle.json').write_bytes(json.dumps(bundle,ensure_ascii=False,separators=(',',':')).encode())
    names=('worker.js','wasmoon.js','sha256.js','runtime.wasm','bundle.json')
    assets={name:{'sha256':hashlib.sha256((out/name).read_bytes()).hexdigest(),'bytes':(out/name).stat().st_size}for name in names}
    manifest={'schema_version':1,'protocol':'pattern-browser-v1','assets':assets,'source_files':{name:hashlib.sha256(value.encode()).hexdigest()for name,value in source.items()},'runtime_files':runtime_manifest,'hash_files':hash_manifest}
    manifest['source_digest']=hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()
    (out/'assets.json').write_bytes((json.dumps(manifest,indent=2)+'\n').encode())
    licenses=out/'licenses';licenses.mkdir(exist_ok=True)
    for name in('LICENSE','LUA-LICENSE.txt'):shutil.copyfile(vendor/name,licenses/name)
    shutil.copyfile(hash_vendor/'LICENSE',licenses/'hash-wasm-MIT.txt')
    shutil.copyfile(hash_vendor/'SHA256-C-LICENSE.txt',licenses/'SHA256-C-LICENSE.txt')
    return out
if __name__=='__main__':print(package())

"""Reconstruct the canonical release source in a fresh directory with real dependencies."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import zlib
import PIL
import pypdf

from release_candidate import archive, checksums, extract, source_snapshot

ROOT=Path(__file__).resolve().parents[1]
SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
READ=lambda p:json.loads(p.read_text(encoding='utf8'))


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,default=ROOT/'build/release-source-check')
    a=ap.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    source,files=source_snapshot(ROOT)
    source_data=(json.dumps(source,sort_keys=True,ensure_ascii=False,indent=2)+'\n').encode()
    files['SOURCE.json']=(source_data,'100644');files['SHA256SUMS']=(checksums(files),'100644')
    package=archive(out/'florilegium-source.zip','florilegium',files)
    phases=[]
    with tempfile.TemporaryDirectory(prefix='Florilegium source only ',dir=out.parent)as temporary:
        kit=extract(out/'florilegium-source.zip',Path(temporary))
        actual=READ(kit/'SOURCE.json');assert actual==source
        for n,v in source['files'].items():assert SHA(kit/n)==v['sha256']
        def run(name,arguments,timeout):
            started=time.perf_counter()
            p=subprocess.run([sys.executable,*arguments],cwd=kit,capture_output=True,timeout=timeout)
            (out/(name+'.stdout.log')).write_bytes(p.stdout);(out/(name+'.stderr.log')).write_bytes(p.stderr)
            assert p.returncode==0,(name,p.stdout[-3000:],p.stderr[-2000:])
            phases.append({'name':name,'seconds':time.perf_counter()-started,'exit_code':p.returncode,
                           'stdout_sha256':SHA(out/(name+'.stdout.log')),'stderr_sha256':SHA(out/(name+'.stderr.log'))})
        # Public entrypoint, all mandatory examples, signals, symlink controls,
        # independent Unicode output paths and exact validated-instance replay.
        run('all-family-cli',['tools/clicheck.py'],18000)
        receipts=list((kit/'build/cli').glob('*/receipt.json'));assert len(receipts)==1
        cli=READ(receipts[0]);assert len(cli['families'])==22
        assert all(cli['failures'][k]for k in ('symlink_checked','signal_cancellation_checked','unicode_paths_checked'))
        # This is the existing actual dual-engine suite, including placements,
        # convergence, negative examples, and native PDF/raster comparisons.
        run('native-dual-adapters',['tools/pattern_dual_tex_consumer.py'],18000)
        duals=list((kit/'build/pattern-dual').glob('*/receipt.json'));assert len(duals)==1
        dual=READ(duals[0]);assert dual['native_no_shell_escape']
        run('source-browser-build',['tools/webpackage.py'],180)
        web=kit/'build/web';assets={p.relative_to(web).as_posix():SHA(p)for p in sorted(web.rglob('*'))if p.is_file()};assert len(assets)>=16
        # Reassembly from SOURCE.json uses no Git metadata or original checkout.
        rebuilt=out/'rebuilt-source';run('source-only-reassembly',['tools/release_candidate.py','--source-only','--output',str(rebuilt)],180)
        assert SHA(rebuilt/'florilegium-source.zip')==package['sha256']
        for n,v in source['files'].items():
            assert SHA(kit/n)==v['sha256'],('Clean checks modified source',n)
        copied=out/'cli-receipt.json';shutil.copyfile(receipts[0],copied)
        copied=out/'dual-receipt.json';shutil.copyfile(duals[0],copied)
        versions={'python':platform.python_version(),'platform':platform.platform(),'zlib':zlib.ZLIB_RUNTIME_VERSION,
                  'pypdf':pypdf.__version__,'Pillow':PIL.__version__}
        for executable in ('texlua','lualatex','xelatex','pdfinfo'):
            option='-v' if executable=='pdfinfo' else '--version'
            version=subprocess.run([executable,option],capture_output=True,timeout=30)
            assert version.returncode==0,(executable,version.stderr)
            lines=(version.stdout+version.stderr).decode('utf8',errors='replace').splitlines();assert lines
            versions[executable]=lines[0]
        result={'schema_version':1,'status':'passed','revision':source['revision'],'tree':source['tree'],
                'source_zip':package,'source_manifest_sha256':hashlib.sha256(source_data).hexdigest(),
                'source_files_verified':len(source['files']),'all_family_cli_profiles':22,
                'native_dual_engines':2,'source_only_reassembly_byte_equal':True,
                'source_and_output_paths_with_spaces':True,'cli_unicode_output_path':cli['failures']['unicode_paths_checked'],
                'browser_assets':assets,'phases':phases,'dependency_versions':versions,
                'scope':'Actual extracted canonical source, declared system dependencies and native TeX executables. No original source directory used for the build.'}
        (out/'receipt.json').write_text(json.dumps(result,sort_keys=True,indent=2)+'\n',encoding='utf8')
        print(json.dumps(result,sort_keys=True))


if __name__=='__main__':main()

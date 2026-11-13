"""Build the offline gallery from current native review bundles and collection output."""
import argparse
import csv
import hashlib
from html import escape
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
READ = lambda p: json.loads(p.read_text(encoding='utf8'))
SHA = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def dump(p, value):
    p.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)+'\n', encoding='utf8')


def copy_file(source, destination, sha=None):
    assert source.is_file() and not source.is_symlink(), source
    if sha is not None:
        assert SHA(source) == sha, source
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def child(root, name):
    p = root/name
    assert p.resolve().is_relative_to(root.resolve())
    return p


def copy_bundle(source, dest):
    result = READ(source/'result.json')
    assert result['status'] == 'complete'
    for name, digest in result['outputs'].items():
        assert '/' not in name and '\\' not in name
        copy_file(child(source, name), child(dest, name), digest)
    copy_file(source/'result.json', dest/'result.json')
    return result['outputs']


def bibliography():
    with (ROOT/'docs/research/COVERAGE.csv').open(encoding='utf8', newline='') as f:
        rows = list(csv.DictReader(f))
    return {x['capability_id']: x for x in rows}


def collection(out, source):
    receipts = list(source.glob('*/receipt.json'))
    assert len(receipts) == 1, ('Expected one current collection receipt', receipts)
    receipt = receipts[0]
    v = READ(receipt)
    assert v['checks'] > 0
    target = out/'collection'
    for name, digest in v['outputs'].items():
        copy_file(child(receipt.parent, name), child(target, name), digest)
    copy_file(receipt, target/'receipt.json')
    copy_file(receipt.parent/'oracle.json', target/'oracle.json')
    return {'recipe': 'collection/original-collection.json', 'receipt': 'collection/receipt.json',
            'oracle': 'collection/oracle.json', 'outputs': v['outputs'], 'source_digest': v['source_digest']}


def profile_markup(row):
    id = escape(row['id'])
    options = []
    for mode in ('canonical', 'polished'):
        p = f'profiles/{id}/{mode}'
        label = 'Canonical' if mode == 'canonical' else escape(row['variant'])
        options.append(f'<figure><img loading="lazy" src="{p}/pattern.svg" alt="{escape(row["title"])}: {label}">'
                       f'<figcaption>{label}<div class="links"><a href="{p}/pattern.pdf">PDF</a> '
                       f'<a href="{p}/pattern.svg">SVG</a> <a href="{p}/recipe.json">Recipe</a> '
                       f'<a href="{p}/record.json">Build record</a></div></figcaption></figure>')
    ids = ', '.join(row['coverage'])
    scopes = '; '.join(sorted(set(row['scope_kinds'])))
    return (f'<article id="{id}"><h2>{escape(row["title"])}</h2><p>{escape(row["note"])}</p>'
            f'<p class="meta">{escape(row["family"])} · {escape(ids)} · {escape(scopes)}</p>'
            f'<div class="pair">{"".join(options)}</div></article>')


def html_page(rows):
    products = [('Book collection', 'collection-1.svg', 'collection.pdf'),
                ('Facing-page aperiodic view', 'collection-2.svg', 'collection-2.pdf'),
                ('Knot and botanical hybrid', 'hybrid.svg', 'hybrid.pdf'),
                ('Decorated Penrose patch', 'decorated.svg', 'decorated.pdf')]
    collection_html = ''.join(f'<figure><img src="collection/{svg}" alt="{escape(label)}"><figcaption>'
                              f'<a href="collection/{pdf}">{escape(label)} · PDF</a></figcaption></figure>'
                              for label, svg, pdf in products)
    links = ''.join(f'<li><a href="#{escape(r["id"])}">{escape(r["title"])}</a></li>' for r in rows)
    return ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<title>Florilegium · Pattern atlas</title><link rel="stylesheet" href="atlas.css">'
            '<link rel="icon" type="image/svg+xml" href="profiles/inline/canonical/pattern.svg"></head><body>'
            '<header><p class="eyebrow">FLORILEGIUM / THE PATTERN PLATFORM</p><h1>Pattern atlas</h1>'
            '<p>Twenty-two generated profiles, with original method fixtures and separate presentation views.</p>'
            '<p><a href="README.md">Reproduce the atlas</a> · <a href="gallery.json">Artifact metadata</a> · '
            '<a href="SHA256SUMS">Checksums</a></p></header><main>'
            '<section id="collection"><h2>Compass Garden</h2><p>A book collection, a facing-page aperiodic spread and a knot with a botanical attachment.</p>'
            f'<div class="collection">{collection_html}</div><p><a href="collection/original-collection.json">Collection recipe and layout record</a> · '
            '<a href="collection/receipt.json">Validation</a></p></section>'
            f'<nav aria-label="Pattern profiles"><h2>Browse profiles</h2><ul>{links}</ul></nav>'
            + ''.join(map(profile_markup, rows))
            + '</main><footer>Finite fixtures and render views. Read the method notes for the scope of each result.</footer></body></html>\n')


CSS = '''*{box-sizing:border-box}body{margin:0;background:#f3f2eb;color:#18251f;font-family:system-ui,sans-serif}
header,main,footer{max-width:74rem;margin:auto;padding:1.5rem 1.6rem}header{padding-top:3rem;border-bottom:1px solid #c5c9ba}
h1,h2{font-family:Georgia,serif;font-weight:500}h1{font-size:clamp(3rem,8vw,6rem);line-height:1;margin:.15em 0 .25em}h2{font-size:1.8rem;margin:.2em 0}
p,li{line-height:1.6}.eyebrow,.meta{font-size:.83rem;color:#45594d}.eyebrow{letter-spacing:.14em}a{color:#1b5e4b;text-underline-offset:.18em}
a:focus-visible{outline:3px solid #a46a30;outline-offset:3px}article,section,nav{padding:1.2rem 0;border-bottom:1px solid #c5c9ba}
nav ul{columns:3;margin-top:.5rem;padding-left:1.2rem}.pair,.collection{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:1rem}
.collection{grid-template-columns:repeat(4,minmax(0,1fr))}figure{margin:0;background:#fff;border:1px solid #d7d8cf;border-radius:.45rem;overflow:hidden}
img{display:block;width:100%;height:clamp(10rem,30vw,21rem);object-fit:contain;padding:1.1rem}figcaption{padding:.7rem 1rem;background:#f9f8f3;border-top:1px solid #d7d8cf}
.links{display:flex;gap:.7em;flex-wrap:wrap;font-size:.87rem;margin-top:.35em}footer{color:#45594d;font-size:.9rem}
@media(max-width:47rem){nav ul{columns:2}.collection{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:30rem){header,main,footer{padding-inline:1rem}nav ul{columns:1}.pair{grid-template-columns:1fr}img{height:clamp(13rem,61vw,19rem);padding:.75rem}}
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--review', type=Path, default=ROOT/'build/export-review')
    ap.add_argument('--collection', type=Path, default=ROOT/'build/collection')
    ap.add_argument('--output', type=Path, default=ROOT/'build/pattern-atlas')
    ap.add_argument('--lua', default='texlua')
    ap.add_argument('--lua-arg', action='append', default=[])
    a = ap.parse_args()
    review, out = a.review.resolve(), a.output.resolve()
    canonical = READ(ROOT/'examples/cli/catalog.json')['examples']
    spec = READ(ROOT/'examples/gallery/profiles.json')['profiles']
    checked = READ(review/'export-integrity.json')
    assert checked['status'] == 'passed'
    assert [x['id'] for x in canonical] == [x['id'] for x in spec] == [x['id'] for x in checked['profiles']]
    batch = READ(review/'batch.json');assert len(batch['items']) == len(spec) == 22
    coverage = bibliography();out.mkdir(parents=True)
    collection_record = collection(out, a.collection.resolve())
    command = [sys.executable, 'tools/pattern.py', '--lua', a.lua, '--timeout', '900']
    if out.is_relative_to(ROOT):
        command.append('--allow-source-output')
    for arg in a.lua_arg:
        command += ['--lua-arg', arg]
    rows = []
    for item, fixture, audited in zip(spec, canonical, checked['profiles']):
        name = item['id'];assert name.replace('-', '').isalnum()
        folder = child(review, batch['items'][name]['output']);base = out/'profiles'/name
        base.mkdir(parents=True)
        source = ROOT/'examples/cli'/fixture['recipe'];copy_file(source, base/'source.recipe', fixture['sha256'])
        before = copy_bundle(folder, base/'canonical')
        assert before['pattern.pdf'] == audited['exports']['pattern']['pdf_sha256']
        assert before['pattern.svg'] == audited['exports']['pattern']['svg_sha256']
        recipe = READ(folder/'recipe.json');recipe['id'] += '/atlas'
        style = recipe['design']['style']
        if 'native_style' in item:
            style.update(item['native_style'])
        else:
            style['output_profile'] = {'schema_version':1, 'mode':'palette', 'fill':item['fill'], 'stroke':item['stroke']}
        revision = base/'presentation.recipe';dump(revision, recipe)
        run = subprocess.run(command+['render','--from',str(folder),'--updated-recipe',str(revision),'--output',str(base/'polished')],
                             cwd=ROOT,capture_output=True,timeout=930)
        assert run.returncode == 0, (name, run.stdout[-2000:], run.stderr[-1000:])
        report = json.loads(run.stdout);assert report['status'] == 'complete'
        revised = READ(base/'polished/result.json');after = revised['outputs']
        for path, h in after.items():assert SHA(child(base/'polished',path)) == h
        record = READ(base/'polished/record.json');assert record['status']=='complete' and record['validation']['status']=='passed'
        assert record['lineage'][0]['role'] == 'validated-style-view-revision'
        assert record['lineage'][0]['parent_ref'] == READ(folder/'record.json')['id']
        assert before['instance.json'] == after['instance.json'] and before['view.json'] == after['view.json']
        assert before['pattern.pdf'] != after['pattern.pdf'] and before['pattern.svg'] != after['pattern.svg']
        lines = [coverage[id] for id in item['coverage']]
        rows.append({**item,'family':fixture['family'],'source_recipe_sha256':fixture['sha256'],
                     'fixture_source':fixture['source'],'source_ids':sorted({s for line in lines for s in line['source_ids'].split(';')}),
                     'scope_kinds':sorted({line['scope_kind'] for line in lines}),
                     'canonical_files':before,'polished_files':after,
                     'instance_preserved':True,'view_preserved':True,'validation_status':record['validation']['status'],
                     'native_source_digest':record['source']['digest']})
        print('Atlas profile validated',name,flush=True)
    for n in ('LICENSE','docs/fonts/GUST-FONT-LICENSE.md','docs/fonts/LPPL-1.3c.md','docs/fonts/README-PatternMicrography.md','docs/fonts/README-PatternSceneFixture.md',
              'docs/research/licenses/HATVIZ-BSD-3-Clause.txt','docs/research/SOURCES.md','docs/research/BIBLIOGRAPHY.json','docs/research/COVERAGE.csv'):
        copy_file(ROOT/n,out/'notices'/Path(n).name)
    copy_file(ROOT/'examples/gallery/REPRODUCE.md',out/'README.md')
    source_paths=sorted([*ROOT.glob('*.lua'),ROOT/'tools/make-gallery.py',ROOT/'examples/gallery/profiles.json',ROOT/'examples/gallery/REPRODUCE.md'])
    dump(out/'gallery.json',{'schema_version':1,'status':'passed','profiles':rows,'collection':collection_record,
                            'sources':{p.relative_to(ROOT).as_posix():SHA(p) for p in source_paths},
                            'review_integrity_sha256':SHA(review/'export-integrity.json'),
                            'scope':'Actual generated canonical exports and separately named presentation variants; both carry replayable validated instances.'})
    (out/'index.html').write_text(html_page(rows),encoding='utf8')
    (out/'atlas.css').write_text(CSS,encoding='utf8')
    files=[p for p in sorted(out.rglob('*')) if p.is_file()]
    (out/'SHA256SUMS').write_text(''.join(SHA(p)+'  '+p.relative_to(out).as_posix()+'\n' for p in files),encoding='utf8')


if __name__ == '__main__':
    main()

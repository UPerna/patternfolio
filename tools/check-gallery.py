"""Verify the generated gallery's local links, coverage and source bindings."""
import argparse
import csv
import functools
import hashlib
from html.parser import HTMLParser
import http.server
import json
from pathlib import Path
import re
import subprocess
import threading
from urllib.parse import unquote, urlsplit
from export_review import geometry, svg_info

ROOT = Path(__file__).resolve().parents[1]
SHA = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
READ = lambda p: json.loads(p.read_text(encoding='utf8'))


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.links = []
        self.images = 0

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids
            self.ids.add(attrs['id'])
        self.links.extend(attrs[k] for k in ('href','src') if k in attrs)
        if tag == 'img':
            assert attrs['alt'].strip()
            self.images += 1


def link(root, relative, ids=None):
    uri = urlsplit(relative)
    assert not uri.scheme and not uri.netloc
    if uri.path:
        target = (root/unquote(uri.path)).resolve()
        assert target.is_relative_to(root.resolve()) and target.is_file(), relative
    elif uri.fragment and ids is not None:
        assert uri.fragment in ids, relative


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('gallery', type=Path)
    ap.add_argument('--playwright')
    ap.add_argument('--executable')
    ap.add_argument('--browser-output', type=Path, default=ROOT/'build/gallery-browser')
    a = ap.parse_args()
    base = a.gallery.resolve();p=Page();p.feed((base/'index.html').read_text(encoding='utf8'))
    assert p.images==48
    for name in p.links:link(base,name,p.ids)
    for path in re.findall(r'\]\(([^\s)]+)\)',(base/'README.md').read_text(encoding='utf8')):link(base,path)
    files = {}
    for row in (base/'SHA256SUMS').read_text(encoding='utf8').splitlines():
        digest,name = row.split('  ',1)
        assert name not in files
        link(base,name)
        assert SHA(base/name) == digest
        files[name] = digest
    assert set(files) == {x.relative_to(base).as_posix()for x in base.rglob('*')if x.is_file()}-{'SHA256SUMS'}
    metadata = READ(base/'gallery.json');assert metadata['status']=='passed' and len(metadata['profiles'])==22
    for name,h in metadata['sources'].items():assert SHA(ROOT/name)==h,name
    for row in metadata['profiles']:
        assert row['validation_status']=='passed' and row['instance_preserved'] and row['view_preserved']
        assert row['id'] in p.ids and row['coverage'] and row['source_ids']
        for mode in ('canonical','polished'):
            folder=base/'profiles'/row['id']/mode
            assert READ(folder/'result.json')['outputs']==row[mode+'_files']
            for name,h in row[mode+'_files'].items():assert SHA(folder/name)==h
        assert SHA(base/'profiles'/row['id']/'source.recipe')==row['source_recipe_sha256']
        src=base/'profiles'/row['id'];original,original_size=svg_info(src/'canonical/pattern.svg');presentation,presentation_size=svg_info(src/'polished/pattern.svg')
        assert original_size==presentation_size and geometry(original)==geometry(presentation), row['id']
    for name,digest in metadata['collection']['outputs'].items():assert SHA(base/'collection'/name)==digest
    with (ROOT/'docs/research/COVERAGE.csv').open(encoding='utf8',newline='')as f:
        ledger=list(csv.DictReader(f))
    assert len([row for row in ledger if row['priority']=='mandatory'])==46
    for row in ledger:
        if row['priority']=='mandatory':
            assert row['status']=='passed' and row['evidence']
            for name in row['evidence'].split(';'):link(ROOT,name.strip())
    print('Gallery:',len(files),'files,',p.images,'real SVG images,',len(p.links),'valid links and 22 verified profiles')
    if a.playwright:
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(base)))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            command=['node',str(ROOT/'tools/gallerycheck.cjs'),f'http://127.0.0.1:{server.server_port}/',a.playwright,str(a.browser_output.resolve())]
            if a.executable:command.append(a.executable)
            subprocess.run(command,cwd=ROOT,check=True,timeout=180)
        finally:
            server.shutdown();server.server_close()


if __name__=='__main__':main()

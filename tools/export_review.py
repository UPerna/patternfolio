"""Build and inspect clean/diagnostic/monochrome vector exports for all profiles."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SVG = '{http://www.w3.org/2000/svg}'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, timeout=180):
    return subprocess.check_output(command, cwd=ROOT, timeout=timeout).decode('utf8')


def svg_info(path):
    svg = ET.parse(path).getroot()
    assert svg.tag == SVG + 'svg'
    assert all(svg.attrib[k].endswith('cm') for k in ('width', 'height'))
    width, height = [float(svg.attrib[k][:-2]) for k in ('width', 'height')]
    assert width > 0 and height > 0
    assert [float(x) for x in svg.attrib['viewBox'].split()] == [0, 0, width, height]
    assert not any(n.tag.removeprefix(SVG) in {'image', 'script', 'foreignObject'} for n in svg.iter())
    for node in svg.iter():
        assert all(not k.endswith('href') or v.startswith('#') for k, v in node.attrib.items())
        if 'stroke-width' in node.attrib:
            assert float(node.attrib['stroke-width']) > 0
            assert node.attrib['stroke-linecap'] in ('butt', 'round', 'square')
            assert node.attrib['stroke-linejoin'] in ('miter', 'round', 'bevel')
    return svg, [width, height]


def geometry(svg):
    return [(node.tag, {k: v for k, v in node.attrib.items() if k not in ('fill', 'stroke')})
            for node in svg.iter()]


def inspect_pdf(pdf, size, local):
    if local:
        from pypdf import PdfReader
        from pypdf.generic import ContentStream
        reader = PdfReader(pdf)
        assert len(reader.pages) == 1
        page = reader.pages[0]
        boxes = {key: list(map(float, getattr(page, key.lower())))
                 for key in ('MediaBox', 'CropBox', 'BleedBox', 'TrimBox')}
        assert all(abs(float(p)*2.54/72-cm) < 1e-6 for p, cm in zip((page.mediabox.width, page.mediabox.height), size))
        assert not page.images
        operators = [op for _, op in ContentStream(page.get_contents(), reader).operations]
        assert b'W' in operators or b'W*' in operators
        return boxes, page.extract_text().split()
    info = run(['pdfinfo', '-box', str(pdf)])
    assert re.search(r'^Pages:\s+1\s*$', info, re.M)
    match = re.search(r'Page size:\s+([\d.]+) x ([\d.]+)', info)
    assert match and all(abs(float(p)*2.54/72-cm) < .002 for p, cm in zip(match.groups(), size))
    boxes = {key: list(map(float, value.split())) for key, value in
             re.findall(r'^(MediaBox|CropBox|BleedBox|TrimBox):\s+([^\n]+)', info, re.M)}
    assert len(run(['pdfimages', '-list', str(pdf)]).splitlines()) == 2, (str(pdf), 'raster content')
    return boxes, run(['pdftotext', '-enc', 'UTF-8', '-raw', str(pdf), '-']).split()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'build/export-review')
    parser.add_argument('--lua', default='texlua')
    parser.add_argument('--lua-arg', action='append', default=[])
    parser.add_argument('--inspect-existing', action='store_true')
    parser.add_argument('--local-pdf-reader', action='store_true')
    a = parser.parse_args()
    output = a.output.resolve()
    if not a.inspect_existing:
        command = [sys.executable, 'tools/pattern.py', '--lua', a.lua, '--timeout', '900']
        if output.is_relative_to(ROOT):
            command.append('--allow-source-output')
        for value in a.lua_arg:
            command += ['--lua-arg', value]
        result = json.loads(run(command + ['batch', 'examples/cli/all-families.json', '--output', str(output)], 19800))
        assert result['status'] == 'complete' and result['failed_items'] == 0
        subprocess.run([a.lua, *a.lua_arg, 'tools/export_review.lua', str(output)], cwd=ROOT, check=True, timeout=2400)
    catalog = json.loads((ROOT/'examples/cli/catalog.json').read_text(encoding='utf8'))['examples']
    variants = json.loads((output/'export-review.json').read_text(encoding='utf8'))
    assert [r['id'] for r in variants['profiles']] == [r['id'] for r in catalog]
    rows = []
    for row, expected_recipe in zip(variants['profiles'], catalog):
        folder = output/row['folder']
        assert folder.resolve().is_relative_to(output) and 0 < row['endpoint_marks'] <= row['diagnostic_limit']
        assert digest(ROOT/'examples/cli'/expected_recipe['recipe']) == expected_recipe['sha256']
        for name in ('recipe', 'instance', 'scene'):
            assert digest(folder/(name+'.json')) == row[name+'_sha256']
        generated = json.loads((folder/'result.json').read_text(encoding='utf8'))
        assert generated['status'] == 'complete'
        for name in ('pattern.pdf', 'pattern.svg', 'instance.json', 'scene.json', 'view.json', 'recipe.json'):
            assert digest(folder/name) == generated['outputs'][name]
        for name, expected in row['outputs'].items():
            assert digest(folder/name) == expected
        clean, size = svg_info(folder/'pattern.svg')
        mono, mono_size = svg_info(folder/'monochrome.svg')
        diagnostic, diagnostic_size = svg_info(folder/'diagnostic.svg')
        _, crop_size = svg_info(folder/'crop.svg')
        assert size == mono_size == diagnostic_size and geometry(clean) == geometry(mono), row['id']
        assert len(list(diagnostic.iter(SVG+'path'))) > len(list(clean.iter(SVG+'path')))
        assert all(abs(c - full/4) < 1e-7 for c, full in zip(crop_size, size))
        exports = {}
        for name in ('pattern', 'diagnostic', 'monochrome'):
            pdf = folder/(name+'.pdf')
            boxes, extracted = inspect_pdf(pdf, size, a.local_pdf_reader)
            assert len(boxes) == 4 and len({tuple(s) for s in boxes.values()}) == 1
            if name == 'pattern':
                clean_text = extracted
            else:
                assert extracted == clean_text, (row['id'], name, 'search text changed')
            exports[name] = {'pdf_sha256': digest(pdf), 'svg_sha256': digest(folder/(name+'.svg')),
                             'page_boxes_bp': boxes, 'search_words': len(extracted)}
        if row['id'] == 'micrography':
            assert clean_text and len(list(clean.iter(SVG+'text'))) > 0
        rows.append({'id': row['id'], 'source_recipe_sha256': expected_recipe['sha256'],
                     'canvas_cm': size, 'crop_cm': crop_size, 'exports': exports})
        print('PDF/SVG export integrity', row['id'], flush=True)
    result = {'schema_version': 1, 'status': 'passed', 'profiles': rows,
              'pdf_reader': 'pypdf' if a.local_pdf_reader else 'Poppler',
              'variant_manifest_sha256': digest(output/'export-review.json'),
              'scope': 'Physical page boxes, vector content and logical text; SVG geometry-preserving monochrome and bounded diagnostics. No Office or physical print compatibility claim.'}
    (output/'export-integrity.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf8')


if __name__ == '__main__':
    main()

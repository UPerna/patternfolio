"""Compare actual common-pattern LuaLaTeX/XeLaTeX books and build failures."""
import hashlib
import json
from pathlib import Path
import subprocess
import unicodedata
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from pypdf import PdfReader, PdfWriter
from pypdf.generic import RectangleObject, DecodedStreamObject, NameObject
from pattern_tex_pdf import forms, locate
import pattern_tex_consumer as consumer
from tex_build_consumer import build_cases

ROOT = Path(__file__).resolve().parents[1]
COORDINATE_TOLERANCE = 2 * 2.54 / (72.27 * 65536)  # two TeX scaled points, cm


def fingerprint():
    _, files = consumer.fingerprint()
    for name in ('pattern_dual_tex_consumer.py', 'tex_build_consumer.py', 'build_statecheck.py', 'check-pattern-xetex.lua'):
        files['tools/' + name] = hashlib.sha256((ROOT / 'tools' / name).read_bytes()).hexdigest()
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(), files


def compare_data(a, b, path, differences):
    if isinstance(a, (int, float)) and not isinstance(a, bool):
        assert isinstance(b, (int, float)) and not isinstance(b, bool), path
        error = abs(a - b)
        assert error <= COORDINATE_TOLERANCE, (path, a, b, error)
        if error:
            differences.append({'path': path, 'absolute_difference': error})
    elif isinstance(a, dict):
        assert isinstance(b, dict) and a.keys() == b.keys(), (path, a.keys(), getattr(b, 'keys', lambda: [])())
        for key in a:
            compare_data(a[key], b[key], path + '/' + key, differences)
    elif isinstance(a, list):
        assert isinstance(b, list) and len(a) == len(b), (path, 'sequence length')
        for i, (x, y) in enumerate(zip(a, b)):
            compare_data(x, y, path + '/' + str(i), differences)
    else:
        assert a == b, (path, a, b)


def color_mask(image):
    red, green, blue = image.convert('RGB').split()
    high = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    low = ImageChops.darker(ImageChops.darker(red, green), blue)
    return ImageChops.subtract(high, low).point(lambda value: 255 if value > 15 else 0)


def component_coverage(mask, other):
    """A missing small glyph cannot disappear inside a whole-page mean."""
    pixels = mask.get_flattened_data() if hasattr(mask, 'get_flattened_data') else mask.getdata()
    remaining = {i for i, value in enumerate(pixels) if value}
    nearby = other.filter(ImageFilter.MaxFilter(3)).load()
    width, height = mask.size
    minimum, components = 1.0, 0
    while remaining:
        first = remaining.pop(); queue = [first]; count = covered = 0
        while queue:
            point = queue.pop(); x, y = point % width, point // width
            count += 1; covered += bool(nearby[x, y])
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    xx, yy = x + dx, y + dy
                    candidate = yy * width + xx
                    if 0 <= xx < width and 0 <= yy < height and candidate in remaining:
                        remaining.remove(candidate); queue.append(candidate)
        coverage = covered / count
        # Tiny detached glyph details must all survive; larger connected ink
        # permits at most two percent coverage variation within one AA pixel.
        assert coverage == 1 if count <= 10 else coverage >= .98, (count, coverage)
        minimum = min(minimum, coverage); components += 1
    return {'components': components, 'minimum_coverage': minimum}


def compare_masks(a, b, name):
    assert a.size == b.size, name
    aa, bb = a.getbbox(), b.getbbox()
    assert aa and bb, (name, 'missing ornament ink')
    assert max(abs(x - y) for x, y in zip(aa, bb)) <= 1, (name, aa, bb)
    union = ImageChops.lighter(a, b).histogram()[255]
    changed = ImageChops.difference(a, b).histogram()[255]
    assert changed / union <= .005, (name, changed, union)
    return {'name': name, 'changed_colored_pixels': changed, 'union_colored_pixels': union,
            'changed_fraction_limit': .005, 'ink_bounds': [aa, bb],
            'coverage_lua_to_xe': component_coverage(a, b), 'coverage_xe_to_lua': component_coverage(b, a)}


def bounds_pixels(bounds, size, media, padding=0):
    x0, y0, x1, y1 = bounds; width, height = size; pw, ph = media
    return (max(0, int(x0 / pw * width) - padding), max(0, int((ph - y1) / ph * height) - padding),
            min(width, round(x1 / pw * width) + padding), min(height, round((ph - y0) / ph * height) + padding))


def page_image(pdf, page, prefix):
    subprocess.run(['pdftoppm', '-f', str(page), '-l', str(page), '-r', '144', '-png', '-singlefile', str(pdf), str(prefix)],
                   check=True, capture_output=True)
    return Image.open(str(prefix) + '.png').convert('RGB')


def registered_inline(reader, page_number, source, prefix):
    """Register actual page paint, retaining its clips and foreground occlusion.

    Placement is checked independently. Engine PDF serializers round page
    translations differently; rasterizing on those slightly different grids
    can flip antialias pixels even for identical imported drawing commands.
    Only a positive uniform inclusion transform may be undone here.
    """
    original = reader.pages[page_number - 1]
    assert int(original.get('/Rotate', 0)) % 360 == 0, 'Rotated book pages require a separately measured frame'
    measured = locate(forms(reader, original), source)
    m = measured['matrix']
    assert m[0] > 0 and m[3] > 0 and abs(m[0] - m[3]) < 1e-8, ('Nonuniform inline inclusion', m)
    assert abs(m[1]) < 1e-8 and abs(m[2]) < 1e-8, ('Rotated/reflected inline inclusion', m)
    scale = m[0]
    registration = (1 / scale, 0, 0, 1 / scale, -m[4] / scale, -m[5] / scale)
    writer = PdfWriter()
    page = writer.add_page(original)
    # Wrap the original decoded page bytes without parsing/re-encoding its
    # text-show strings. Older pypdf serializers can change two-byte CIDs.
    stream = DecodedStreamObject()
    matrix = ' '.join(format(value, '.17g') for value in registration)
    original_bytes = original.get_contents().get_data()
    crop = original.cropbox
    clip = ' '.join(format(float(value), '.17g') for value in
                    (crop.left, crop.bottom, crop.width, crop.height)) + ' re W n\n'
    registered_bytes = ('q\n' + matrix + ' cm\n' + clip).encode('ascii') + original_bytes + b'\nQ\n'
    stream.set_data(registered_bytes)
    page[NameObject('/Contents')] = writer._add_object(stream)
    box = PdfReader(source).pages[0].mediabox
    page.mediabox = RectangleObject(box)
    page.cropbox = RectangleObject(box)
    destination = Path(str(prefix) + '.pdf')
    writer.write(destination)
    assert PdfReader(destination).pages[0].get_contents().get_data() == registered_bytes, 'Registration changed page paint bytes'
    mask = color_mask(page_image(destination, 1, prefix))
    return mask, {'actual_form_matrix': list(m), 'registration_matrix': list(registration),
                  'source_box_bp': list(map(float, box)), 'actual_book_page_paint_retained': True,
                  'original_page_content_sha256': hashlib.sha256(original_bytes).hexdigest(),
                  'original_page_content_bytes_preserved': True, 'original_page_clip_bp': list(map(float, crop))}


def compare_books(lua_folder, xe_folder, folder):
    books = [lua_folder / 'book', xe_folder / 'book']
    traces = [consumer.read(book / 'book-patterns.json') for book in books]
    declarations = [{d['name']: d for d in trace['declarations']} for trace in traces]
    assert declarations[0].keys() == declarations[1].keys()
    source_scenes = []
    for name, left in declarations[0].items():
        right = declarations[1][name]
        assert left['instance_sha256'] == right['instance_sha256'], (name, 'semantic construction changed between engines')
        a, b = [consumer.read(book / (d['prefix'] + '.scene')) for book, d in zip(books, (left, right))]
        assert a == b, (name, 'original planner-selected scene changed')
        source_scenes.append(name)
    texts = [subprocess.check_output(['pdftotext', '-raw', str(book / 'book.pdf'), '-'], text=True) for book in books]
    normalized = [''.join(unicodedata.normalize('NFKC', text).split()) for text in texts]
    assert normalized[0] and normalized[0] == normalized[1], 'Extracted book letters or reading order differ'
    readers = [PdfReader(book / 'book.pdf') for book in books]
    assert len(readers[0].pages) == len(readers[1].pages) == 4
    numerical, raster = [], []
    for page_number, (a, b) in enumerate(zip(traces[0]['pages'], traces[1]['pages']), 1):
        left, right = {x['name']: x for x in a['outputs']}, {x['name']: x for x in b['outputs']}
        assert left.keys() == right.keys()
        for name in left:
            scenes = [consumer.read(book / (output['prefix'] + '.scene')) for book, output in zip(books, (left[name], right[name]))]
            # These root IDs bind measured page anchors; all drawing data,
            # object references, resources, clip commands and paint still compare.
            for scene in scenes:
                scene.pop('id'); scene.pop('view_ref')
            compare_data(*scenes, f'page/{page_number}/{name}', numerical)
        images = [page_image(book / 'book.pdf', page_number, folder / f'{engine}-page-{page_number}')
                  for engine, book in zip(('lua', 'xe'), books)]
        media = a['geometry']['size']; assert media == b['geometry']['size']
        masks = [color_mask(image) for image in images]
        if left:
            background = [mask.copy() for mask in masks]
            exclusions = []
            for page in (a, b):
                geometry = page['geometry']
                exclusions.extend([geometry['content'], *geometry['running_regions'], *geometry['reservations']])
            for mask in background:
                draw = ImageDraw.Draw(mask)
                for region in exclusions:
                    draw.rectangle(bounds_pixels(region, mask.size, media, padding=1), fill=0)
            raster.append(compare_masks(*background, f'actual-page/{page_number}/background'))
        positions = [page['geometry']['inline_positions'] for page in (a, b)]
        assert [x['name'] for x in positions[0]] == [x['name'] for x in positions[1]]
        for index, pair in enumerate(zip(*positions)):
            boxes = []
            for book, item in zip(books, pair):
                boxes.append([item['x'], item['y'], item['x'] + item['width'], item['y'] + item['height']])
            compare_data(boxes[0], boxes[1], f'page/{page_number}/inline/{index}', numerical)
            paths = [book / (item['prefix'] + '.pdf') for book, item in zip(books, pair)]
            assert paths[0].read_bytes() == paths[1].read_bytes(), (pair[0]['name'], 'shared inline PDF/font resources changed')
            registered = [registered_inline(reader, page_number, source,
                          folder / f'{engine}-page-{page_number}-inline-{index}')
                          for engine, reader, source in zip(('lua', 'xe'), readers, paths)]
            check = compare_masks(*(x[0] for x in registered), f'actual-page/{page_number}/inline/{pair[0]["name"]}')
            check['measured_frame_registration'] = [x[1] for x in registered]
            raster.append(check)
    return {'source_scenes_and_instances': source_scenes, 'drawing_numeric_differences': numerical,
            'coordinate_tolerance_cm': COORDINATE_TOLERANCE, 'actual_book_raster_checks': raster,
            'complete_extracted_letters_and_reading_order_equal': True,
            'font_isolation': 'Shared inline PDF/font bytes compare exactly. Black native TeX body text is excluded from color raster comparisons; its full extracted letter sequence is compared separately.'}


def main():
    digest, source = fingerprint(); folder = ROOT / 'build/pattern-dual' / digest; folder.mkdir(parents=True, exist_ok=True)
    lua_folder, lua = consumer.main('lua')
    xe_folder, xe = consumer.main('xe')
    comparison = compare_books(lua_folder, xe_folder, folder)
    comparison_receipt = {'source_digest': digest, 'source_files': source, 'comparison': comparison,
                          'scope': 'Native book comparison complete; build-fault and inherited gates remain separate'}
    (folder / 'book-comparison.json').write_text(json.dumps(comparison_receipt, indent=2) + '\n', encoding='utf8')
    failures = build_cases(folder / 'build-faults')
    assert {'auxiliaries-lua', 'auxiliaries-xe', 'first-pass-lua', 'first-pass-xe', 'empty-output-lua', 'empty-output-xe',
            'recipe-stale-xe', 'font-stale-xe', 'renderer-stale-xe', 'scene-corruption-xe', 'font-fallback-lua', 'font-fallback-xe'} <= failures.keys()
    assert fingerprint() == (digest, source), 'Native verification did not restore its temporary source mutation'
    receipt = {'schema_version': 1, 'source_digest': digest, 'source_files': source,
               'book_comparison_sha256': hashlib.sha256((folder / 'book-comparison.json').read_bytes()).hexdigest(),
               'engines': {'lua': lua['runtime'], 'xe': xe['runtime']}, 'comparison': comparison, 'build_cases': failures,
               'per_engine_consumers': {engine: hashlib.sha256((path / 'receipt.json').read_bytes()).hexdigest()
                                        for engine, path in (('lua', lua_folder), ('xe', xe_folder))},
               'per_engine_consumer_source_digest': lua['source_digest'], 'native_no_shell_escape': True}
    assert lua['source_digest'] == xe['source_digest']
    (folder / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf8')
    print('Native dual-engine semantic/vector/text/position/ink and build-convergence gates passed', digest)


if __name__ == '__main__':
    main()

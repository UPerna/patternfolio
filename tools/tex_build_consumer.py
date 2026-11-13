"""Native TeX convergence, stale dependency and fallback acceptance fixtures."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import unicodedata
from pypdf import PdfReader
from pypdf.generic import ContentStream, NameObject, TextStringObject, ByteStringObject, ArrayObject
from build import ROOT, build, file_hash


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def dependency_hash(manifest, path):
    return {Path(name).resolve(): digest for name, digest in manifest['dependencies'].items()}[path.resolve()]


def letters(pdf):
    text = subprocess.check_output(['pdftotext', '-raw', str(pdf), '-'], text=True)
    return ''.join(unicodedata.normalize('NFKC', text).split())


def run(source, engine, folder, maximum=6):
    pdf = build(source, engine=engine, output_dir=folder, job_name='source', max_passes=maximum)
    receipt = read(folder / 'source-build.json')
    assert receipt['status'] == 'complete' and receipt['accepted_pass'] >= 2
    assert receipt['final_pdf_sha256'] == file_hash(pdf) and len(PdfReader(pdf).pages) > 0
    return pdf, receipt


def expect_failure(source, engine, folder, message, maximum=6):
    try:
        build(source, engine=engine, output_dir=folder, job_name='source', max_passes=maximum)
    except RuntimeError as error:
        assert message in str(error), str(error)
    else:
        raise AssertionError('Invalid native build was accepted: ' + str(source))
    receipt = read(folder / 'source-build.json')
    assert receipt['status'] == 'failed' and 'accepted_pass' not in receipt
    return receipt


def common_source(folder):
    folder.mkdir(parents=True, exist_ok=True)
    recipe = folder / 'selected.recipe'; shutil.copyfile(ROOT / 'examples/cli/periodic.recipe', recipe)
    source = folder / 'source.tex'
    source.write_text(r'\documentclass{article}\usepackage[a5paper,margin=22mm]{geometry}'
        r'\usepackage[grown,nomargin]{florilegium}\florilegiumpatterndeclare{p}{selected.recipe}'
        r'\begin{document}A shared patterned view.\par\florilegiumpatterninline[2cm]{p}'
        r'\florilegiumpatternpage{p}\end{document}', encoding='utf8')
    return source, recipe


def main_aux_hashes(receipt, folder):
    path = str(folder / 'source.aux')
    return [dict(item['auxiliaries_before_render'])[path] for item in receipt['passes']]


def painted_large_a(pdf):
    # Inspect actual visible text, not merely a hidden searchable fallback label.
    painted = []; reader = PdfReader(pdf)
    showing = {b'Tj', b'TJ', b"'", b'"'}

    def original_glyph_bytes(value):
        # A PDF text-show string contains font character codes, not Unicode.
        # Some pypdf versions autodetect a two-byte CID string as text and
        # re-encode it differently when the filtered stream is serialized.
        if isinstance(value, TextStringObject):
            return ByteStringObject(value.original_bytes)
        if isinstance(value, ArrayObject):
            return ArrayObject([original_glyph_bytes(item) for item in value])
        return value

    def check_forms(resources, seen, depth=0):
        assert depth < 16
        for ref in resources.get('/XObject', {}).get_object().values() if '/XObject' in resources else ():
            obj = ref.get_object()
            if obj.get('/Subtype') != '/Form' or id(obj) in seen:
                continue
            seen.add(id(obj))
            stream = ContentStream(obj, reader)
            assert not any(operator in showing for _, operator in stream.operations), 'Fallback fixture unexpectedly contains Form text; its visibility requires a separate proof'
            check_forms(obj.get('/Resources', resources).get_object(), seen, depth + 1)

    def text(value, cm, tm, font, size):
        scale = abs((cm[0] * cm[3] - cm[1] * cm[2]) * (tm[0] * tm[3] - tm[1] * tm[2])) ** .5
        if 'A' in value and size * scale > 20:
            painted.append({'text': value, 'effective_size_pt': size * scale, 'visibility': 'painted text operators only'})

    for page in reader.pages:
        check_forms(page['/Resources'].get_object(), set())
        stream = ContentStream(page.get_contents(), reader)
        mode = 0; stack = []; visible = []
        for operands, operator in stream.operations:
            if operator == b'q':
                stack.append(mode)
            elif operator == b'Q':
                assert stack; mode = stack.pop()
            elif operator == b'Tr':
                mode = int(operands[0])
            # pypdf can combine adjacent fragments across a Tr change. Remove
            # nonpainting show operators before decoding, not after its visitor.
            if operator not in showing or mode not in (3, 7):
                if operator in showing:
                    operands = [original_glyph_bytes(item) for item in operands]
                visible.append((operands, operator))
        assert not stack
        stream.operations = visible
        page[NameObject('/Contents')] = stream
        page.extract_text(visitor_text=text)
    assert painted, 'Fallback has a searchable label but no visible enlarged initial'
    return painted


def build_cases(folder):
    folder.mkdir(parents=True, exist_ok=True)
    result = {}
    # Real included chapters, all requested lists, and an invisible child-only
    # auxiliary counter: a stable main aux must not hide chapter churn.
    for engine in ('lua', 'xe'):
        case = folder / ('auxiliaries-' + engine); case.mkdir(exist_ok=True)
        source = case / 'Book Ω with spaces.tex'
        source.write_text(r'\documentclass[openany]{book}\usepackage[nomargin]{florilegium}\usepackage{hyperref}'
            r'\begin{document}\tableofcontents\listoffigures\listoftables\include{one}\include{two}\end{document}', encoding='utf8')
        chapter = case / 'one.tex'
        original = (r'\chapter{First chapter}\label{chapter:first}Real auxiliary evidence.'
            r'\begin{figure}[ht]\centering A figure.\caption{A native figure}\label{figure:native}\end{figure}'
            r'\begin{table}[ht]\centering A table.\caption{A native table}\label{table:native}\end{table}\par')
        chapter.write_text(original, encoding='utf8')
        (case / 'two.tex').write_text(r'\chapter{Second chapter}Chapter~\ref{chapter:first}, Figure~\ref{figure:native}, Table~\ref{table:native}.', encoding='utf8')
        out = case / 'out'; pdf, stable = run(source, engine, out)
        names = {Path(path).name for path, digest in stable['passes'][-1]['auxiliaries_before_render'] if digest}
        assert {'source.aux', 'one.aux', 'two.aux', 'source.toc', 'source.lof', 'source.lot', 'source.out'} <= names, names
        churn = (r'\makeatletter\ifdefined\childcounter\else\gdef\childcounter{0}\fi'
                 r'\immediate\write\@auxout{\string\gdef\string\childcounter{\number\numexpr\childcounter+1\relax}}\makeatother')
        try:
            chapter.write_text(original + churn, encoding='utf8')
            failure = expect_failure(source, engine, out, 'did not converge in 3 passes', maximum=3)
            assert 'one.aux' in failure['diagnostic']
            assert len(set(main_aux_hashes(failure, out))) == 1, 'The native main aux was not stable in this child-churn fixture'
        finally:
            chapter.write_text(original, encoding='utf8')
        result['auxiliaries-' + engine] = {'stable_passes': stable, 'chapter_churn_failure': failure}
        # A valid old PDF does not permit a first-pass acceptance.
        first = case / 'first-pass'; first.mkdir(exist_ok=True); shutil.copyfile(pdf, first / 'source.pdf')
        limited = expect_failure(source, engine, first, 'did not converge in 1 passes', maximum=1)
        assert len(limited['passes']) == 1
        result['first-pass-' + engine] = limited
        empty = case / 'empty'; empty.mkdir(exist_ok=True)
        empty_source = case / 'empty.tex'
        empty_source.write_text(r'\documentclass{article}\usepackage[nomargin]{florilegium}\begin{document}\setbox0=\hbox{No shipped page.}\end{document}', encoding='utf8')
        shutil.copyfile(pdf, empty / 'source.pdf')
        seeded_pdf = file_hash(empty / 'source.pdf')
        missing = expect_failure(empty_source, engine, empty, 'missing or incomplete')
        # LuaTeX 1.24 can leave a new zero-byte file when no page ships.
        # The gate is failed acceptance and removal of the valid old PDF;
        # an empty diagnostic artifact is not a completed document.
        rejected = empty / 'source.pdf'
        assert missing['passes'][-1]['compiler_exit'] == 0
        assert not rejected.exists() or rejected.stat().st_size == 0
        assert not rejected.exists() or file_hash(rejected) != seeded_pdf
        missing['seeded_old_pdf_sha256'] = seeded_pdf
        missing['rejected_output'] = {'exists': rejected.exists(),
            'bytes': rejected.stat().st_size if rejected.exists() else None,
            'sha256': file_hash(rejected) if rejected.exists() else None}
        result['empty-output-' + engine] = missing

    source, recipe = common_source(folder / 'recipe-stale-xe'); out = source.parent / 'out'
    _, before = run(source, 'xe', out); old_trace = read(out / 'source-patterns.json')
    record_hash = file_hash(out / 'source.flo')
    old_scene = old_trace['declarations'][0]['hashes']['scene']
    q = read(recipe); assert q['design']['style']['marker'] is True
    q['design']['style']['marker'] = False; recipe.write_text(json.dumps(q), encoding='utf8')
    _, after = run(source, 'xe', out); trace = read(out / 'source-patterns.json')
    assert file_hash(out / 'source.flo') == record_hash and trace['declarations'][0]['hashes']['scene'] != old_scene
    assert any(p['rendered'] for p in after['passes'])
    manifest = read(out / 'source-external.json')
    assert dependency_hash(manifest, recipe) == file_hash(recipe)
    stored = read(out / (trace['declarations'][0]['prefix'] + '.recipe'))
    assert stored['design']['style']['marker'] is False
    result['recipe-stale-xe'] = {'before': before, 'after': after, 'unchanged_record_sha256': record_hash,
        'old_scene_sha256': old_scene, 'new_scene_sha256': trace['declarations'][0]['hashes']['scene']}

    source, _ = common_source(folder / 'renderer-stale-xe'); out = source.parent / 'out'
    _, before = run(source, 'xe', out); record_hash = file_hash(out / 'source.flo')
    old_prefix = read(out / 'source-patterns.json')['declarations'][0]['prefix']
    module = ROOT / 'pattern_xetex.lua'; original = module.read_bytes()
    mutation = original + b'\n-- native invalidation fixture; restored in finally\n'
    snapshot = source.parent / 'renderer-source-snapshot.lua'; snapshot.write_bytes(mutation)
    try:
        module.write_bytes(mutation)
        _, after = run(source, 'xe', out)
        new_prefix = read(out / 'source-patterns.json')['declarations'][0]['prefix']
        assert old_prefix != new_prefix and file_hash(out / 'source.flo') == record_hash
        assert any(p['rendered'] for p in after['passes'])
        assert after['passes'][0]['external_before'] == 'renderer or runtime changed'
    finally:
        module.write_bytes(original)
    result['renderer-stale-xe'] = {'before': before, 'after': after, 'unchanged_record_sha256': record_hash,
                                  'old_prefix': old_prefix, 'new_prefix': new_prefix, 'source_restored_sha256': file_hash(module),
                                  'temporary_source_snapshot': snapshot.relative_to(folder).as_posix(),
                                  'temporary_source_sha256': file_hash(snapshot)}

    # Keep copied test fonts outside uploaded artifact directories; their exact
    # distribution paths and hashes remain in the actual dependency evidence.
    fonts = ROOT / 'build/tex-font-inputs' / folder.parent.name; fonts.mkdir(parents=True, exist_ok=True)
    installed = [Path(subprocess.check_output(['kpsewhich', name], text=True).strip())
                 for name in ('lmroman10-bold.otf', 'lmroman12-regular.otf')]
    assert all(path.is_file() for path in installed)
    font = fonts / 'selected-font.otf'; shutil.copyfile(installed[0], font)
    case = folder / 'font-stale-xe'; case.mkdir(exist_ok=True); source = case / 'source.tex'
    preamble = r'\documentclass{article}\usepackage[a5paper,margin=22mm]{geometry}\usepackage[grown,nomargin]{florilegium}'
    source.write_text(preamble + rf'\florilegiuminitialfont{{{font.as_posix()}}}' +
        r'\begin{document}\florilegiuminitial{A}lphabet.\end{document}', encoding='utf8')
    out = case / 'out'; pdf, before = run(source, 'xe', out)
    old_pdf, old_font, record_hash = file_hash(out / 'source-flo.pdf'), file_hash(font), file_hash(out / 'source.flo')
    shutil.copyfile(installed[1], font)
    pdf, after = run(source, 'xe', out)
    manifest = read(out / 'source-external.json')
    assert file_hash(font) != old_font and file_hash(out / 'source-flo.pdf') != old_pdf
    assert file_hash(out / 'source.flo') == record_hash and dependency_hash(manifest, font) == file_hash(font)
    assert any(p['rendered'] for p in after['passes']) and 'Alphabet' in letters(pdf)
    assert all(item['status'] == 1 for item in manifest['font_results'])
    result['font-stale-xe'] = {'before': before, 'after': after, 'unchanged_record_sha256': record_hash,
        'old_font_sha256': old_font, 'new_font_sha256': file_hash(font), 'old_drawing_sha256': old_pdf,
        'new_drawing_sha256': file_hash(out / 'source-flo.pdf'), 'dependency_manifest': manifest}

    source, _ = common_source(folder / 'scene-corruption-xe'); out = source.parent / 'out'
    _, before = run(source, 'xe', out); trace = read(out / 'source-patterns.json')
    scene = out / (trace['declarations'][0]['prefix'] + '.scene'); original = scene.read_bytes()
    damaged = b'Occupied native scene fixture\n'
    try:
        scene.write_bytes(damaged)
        failure = expect_failure(source, 'xe', out, 'Vector rendering failed;')
        assert scene.read_bytes() == damaged and failure['passes'][-1]['render_exit'] != 0
        log = out / f'source.render-{failure["passes"][-1]["pass"]}.log'
        assert 'existing generated filename has different bytes' in log.read_text(encoding='utf8')
        result['scene-corruption-xe'] = {'before': before, 'failure': failure,
            'preserved_damaged_sha256': hashlib.sha256(damaged).hexdigest(), 'render_log_sha256': file_hash(log)}
    finally:
        scene.write_bytes(original)

    for engine in ('lua', 'xe'):
        case = folder / ('font-fallback-' + engine); case.mkdir(exist_ok=True); source = case / 'source.tex'
        source.write_text(preamble + r'\florilegiuminitialfont{__florilegium_native_missing_font__.otf}' +
            r'\begin{document}\florilegiuminitial{A}lphabet.\end{document}', encoding='utf8')
        out = case / 'out'; pdf, receipt = run(source, engine, out)
        assert 'Alphabet' in letters(pdf)
        logs = list(out.glob('source.render-*.log' if engine == 'xe' else 'source.pass-*.log'))
        assert any('initial font not found' in path.read_text(encoding='utf8') for path in logs)
        if engine == 'xe':
            manifest = read(out / 'source-external.json')
            assert manifest['font_requests'][0]['path'] is False
            assert manifest['font_results'][0]['status'] == 0
        result['font-fallback-' + engine] = {'receipt': receipt, 'visible_enlarged_initial': painted_large_a(pdf),
            'diagnostic_logs': {p.name: file_hash(p) for p in logs}, 'searchable_letter_and_body': True}
    return result

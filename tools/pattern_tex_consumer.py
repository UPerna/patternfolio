"""Build the public LuaLaTeX book and independently measure its actual PDFs."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
import pypdf
import PIL
from pypdf import PdfReader
from build import build,state
from pattern_tex_pdf import forms,placement,raster,colored

ROOT=Path(__file__).resolve().parents[1]


def fingerprint():
    files=[*ROOT.glob('*.lua'),*ROOT.glob('*.sty'),*ROOT.glob('*.def'),
           *ROOT.glob('examples/patterns/*.tex'),*ROOT.glob('examples/patterns/*.recipe')]
    files.extend(ROOT/'tools'/name for name in ('build.py','check-pattern-tex.lua','check-pattern-luatex-host.lua','pattern_tex_consumer.py','pattern_tex_pdf.py','tex-mask-control.lua','tex-inline-constraints.lua'))
    values={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    return hashlib.sha256(json.dumps(values,sort_keys=True).encode()).hexdigest(),values


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def diagnostic_contains(error,message):
    # TeX's print-line limit can split a word in the middle of a diagnostic.
    return ''.join(message.casefold().split()) in ''.join(str(error).casefold().split())


def failure_evidence(case,error,message,engine):
    evidence=read(case/'out/source-build.json');assert evidence['status']=='failed'
    last=evidence['passes'][-1];number=last['pass']
    if last.get('compiler_exit',0)!=0:
        process='compiler';status=last['compiler_exit'];log=case/'out'/f'source.pass-{number}.log'
        assert str(error).startswith(('lualatex' if engine=='lua' else 'xelatex')+' failed;'),str(error)
    else:
        process='renderer';status=last.get('render_exit',0);log=case/'out'/f'source.render-{number}.log'
        assert engine=='xe' and status!=0 and str(error).startswith('Vector rendering failed;'),str(error)
    assert status!=0 and diagnostic_contains(log.read_text(encoding='utf8'),message),(case.name,str(error))
    return {'name':case.name,'process':process,'exit_status':status,
        'compiler_status':'nonzero' if process=='compiler' else 'zero; external renderer nonzero',
        'expected_diagnostic':message,'log_path':log.relative_to(case.parent).as_posix(),
        'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()}


def main(engine='lua'):
    assert engine in ('lua','xe')
    executable='lualatex' if engine=='lua' else 'xelatex'
    digest,source=fingerprint();folder=ROOT/'build'/('pattern-luatex' if engine=='lua' else 'pattern-xetex')/digest;folder.mkdir(parents=True,exist_ok=True)
    book=folder/'book';pdf=build(ROOT/'examples/patterns/book.tex',engine=engine,output_dir=book)
    trace_path=book/'book-patterns.json';before=trace_path.read_bytes();trace=json.loads(before)
    passes=list(book.glob('book.pass-*.log'));assert 2<=len(passes)<=6
    initial=book/'initial-pass-evidence';initial.mkdir(exist_ok=True)
    for path in passes:shutil.copyfile(path,initial/path.name)
    initial_state=state(book,'book',engine)
    assert {'chapter-one.aux','chapter-two.aux'}<={Path(name).name for name,sha in initial_state if sha},initial_state
    pdf=build(ROOT/'examples/patterns/book.tex',engine=engine,output_dir=book)
    assert trace_path.read_bytes()==before,'Shared pattern/view state did not converge with document auxiliaries'
    assert state(book,'book',engine)==initial_state
    reader=PdfReader(pdf);assert len(reader.pages)==len(trace['pages'])==trace['actual_shipped_pages']
    assert trace['unique_generations']==6 and trace['physical_views']>=4
    assert any(p['geometry']['logical_number']!=p['geometry']['index'] for p in trace['pages'])
    by_index={p['geometry']['index']:p for p in trace['pages']}
    assert by_index[2]['geometry']['logical_number']==42 and by_index[2]['geometry']['label']=='xlii'
    assert any(m['kind']=='heading' and m['arg']==0 for m in by_index[2]['geometry']['markers'])
    declarations={x['name']:x for x in trace['declarations']}
    measured=[];inline_pages={}
    for index,page in enumerate(reader.pages,1):
        current=by_index[index];found=forms(reader,page)
        for output in current['outputs']:
            measured.append(placement(found,book/(output['prefix']+'.pdf'),output['crop']))
            assert output['instance_sha256']==declarations[output['name']]['instance_sha256']
        for output in current['geometry']['inline_positions']:
            x,y=output['x'],output['y']
            measured.append(placement(found,book/(output['prefix']+'.pdf'),[x,y,x+output['width'],y+output['height']]))
            inline_pages.setdefault(output['name'],[]).append(index)
    assert inline_pages['hybrid']==[3],('Float asset failed to travel to actual page 3',inline_pages)
    left=next(o for o in by_index[2]['outputs'] if o['name']=='penrose')
    right=next(o for o in by_index[3]['outputs'] if o['name']=='penrose')
    assert left['instance_sha256']==right['instance_sha256']
    width=by_index[2]['geometry']['size'][0]
    assert abs(left['transform'][4]-right['transform'][4]-width)<1e-10
    assert left['transform'][:4]==right['transform'][:4]
    assert len(right['spread_document']['spreads'])==1
    reservations=((.7,9,1.3,12),(1.3,9,2.5,9.6));ink=[]
    for output in by_index[2]['outputs']:
        prefix=book/output['prefix'];image=raster(prefix.with_suffix('.pdf'),book/(output['name']+'-protected'))
        counts=[colored(image,r,output['crop']) for r in reservations]
        assert counts==[0,0],(output['name'],'Pattern ink entered irregular protected callout',counts)
        control=book/(output['name']+'-mask-control.pdf')
        subprocess.run(['texlua',str(ROOT/'tools/tex-mask-control.lua'),str(book/declarations[output['name']]['prefix']),str(prefix),str(control)],cwd=ROOT,check=True,capture_output=True)
        original=raster(control,book/(output['name']+'-unprotected'))
        unprotected=[colored(original,r,output['crop']) for r in reservations]
        if output['name']=='penrose':assert all(count>20 for count in unprotected),'Mask oracle did not remove real source ink'
        ink.append({'name':output['name'],'protected_colored_pixels':counts,'control_colored_pixels':unprotected})
    text=subprocess.check_output(['pdftotext','-raw',str(pdf),'-'],text=True)
    words=' '.join(text.split());expected=read(ROOT/'examples/patterns/micrography.recipe')['design']['inputs']['text']
    assert ' '.join(expected.split()) in words,'Embedded micrography lost reading order/searchable text'
    assert 'A I' in words,'Embedded shared initial/folio lost searchable labels'
    bbox=subprocess.check_output(['pdftotext','-bbox',str(pdf),'-'],text=True)
    (book/'book.bbox.html').write_text(bbox,encoding='utf8')
    xml=ET.fromstring(bbox);callout=[w for w in xml.iter() if w.tag.endswith('word') and w.text=='Callout']
    assert len(callout)==1,'Irregular callout text was lost'
    # The callout is a real foreground word with independently measured PDF bounds.
    callout_bounds={k:float(callout[0].attrib[k])*2.54/72 for k in ('xMin','yMin','xMax','yMax')}
    assert .5<callout_bounds['xMin']<1.5,callout_bounds
    load_order=[];negative=[];negative_evidence=[]
    recipe=(ROOT/'examples/patterns/hybrid.recipe').as_posix()
    for geometry_first in (False,True):
        for hyperref_first in (False,True):
            geometry=r'\usepackage[a5paper,margin=22mm]{geometry}'
            package=r'\usepackage[grown,nomargin,sections]{florilegium}'
            hyperref=r'\usepackage{hyperref}'
            ordered=(geometry if geometry_first else '')+(hyperref if hyperref_first else '')+package+(geometry if not geometry_first else '')+(hyperref if not hyperref_first else '')
            name=f'order-{int(geometry_first)}-{int(hyperref_first)}';case=folder/name;case.mkdir(exist_ok=True)
            path=case/'source.tex';path.write_text(r'\documentclass{article}'+ordered+rf'\florilegiumpatterndeclare{{p}}{{{recipe}}}'+r'\begin{document}\section[Short]{Long heading}\florilegiumpatternpage{p}Load order.\florilegiumpatterninline[1cm]{p}\end{document}',encoding='utf8')
            built=build(path,engine=engine,output_dir=case/'out');assert built.is_file();load_order.append(name)
    case=folder/'discarded-shipout';case.mkdir(exist_ok=True);path=case/'source.tex'
    path.write_text(r'\documentclass{article}\usepackage[a5paper,margin=22mm]{geometry}\usepackage[grown,nomargin]{florilegium}'+rf'\florilegiumpatterndeclare{{p}}{{{recipe}}}'+r'\begin{document}\AddToHookNext{shipout/before}{\DiscardShipoutBox}\florilegiumpatternpage{p}Discard this logical page.\clearpage\florilegiumpatternpage{p}Retain this logical page.\end{document}',encoding='utf8')
    discarded=build(path,engine=engine,output_dir=case/'out');discarded_trace=read(case/'out/source-patterns.json')
    assert len(PdfReader(discarded).pages)==discarded_trace['actual_shipped_pages']==1
    assert discarded_trace['pages'][0]['geometry']['index']==1 and discarded_trace['pages'][0]['geometry']['logical_number']==2
    subprocess.run(['texlua',str(ROOT/'tools/tex-inline-constraints.lua'),str(folder)],cwd=ROOT,check=True)
    inline_constraints={name:(folder/f'{name}.recipe').as_posix() for name in ('inline-stroke-minimum','inline-text-minimum')}
    cases={
      'inline-stroke-minimum':(r'\florilegiumpatterninline[1sp]{p}','actual transformed stroke is below'),
      'inline-text-minimum':(r'\florilegiumpatterninline[1sp]{p}','actual transformed text size is below'),
      'unknown-asset':(r'\florilegiumpatterninline{missing}','unknown asset'),
      'unknown-region':(r'\florilegiumpatternpage[region=invented]{p}','unsupported region'),
      'unknown-control':(r'\florilegiumpatternpage[mirror=true]{p}','I do not know the key'),
      'fully-protected':(r'\florilegiumpatternpage[region=content,padding=0pt]{p}','fully protected'),
      'wrong-spread':(r'\setcounter{page}{42}\florilegiumpatternpage[region=page,spread=left,padding=0pt]{p}','actual even'),
      'late-declaration':(rf'\florilegiumpatterndeclare{{late}}{{{recipe}}}','Can be used only in preamble'),
      'missing-spread-partner':(r'First page.\clearpage\florilegiumpatternpage[region=page,spread=left,padding=0pt]{p}Left page.','no matching right'),
    }
    for name,(body,message) in cases.items():
        case=folder/name;case.mkdir(exist_ok=True);path=case/'source.tex'
        case_recipe=inline_constraints.get(name,recipe)
        path.write_text(r'\documentclass{article}\usepackage[a5paper,margin=22mm]{geometry}\usepackage[grown,nomargin]{florilegium}'+rf'\florilegiumpatterndeclare{{p}}{{{case_recipe}}}'+r'\begin{document}Expected failure.'+body+r'\end{document}',encoding='utf8')
        try:build(path,engine=engine,output_dir=case/'out')
        except RuntimeError as error:
            negative_evidence.append(failure_evidence(case,error,message,engine));negative.append(name)
        else:raise AssertionError('Invalid document compiled successfully: '+name)
    collision=folder/'order-0-0/out';collision_trace=read(collision/'source-patterns.json')
    occupied=collision/(collision_trace['inline'][0]['prefix']+'.pdf');occupied_bytes=b'Occupied verification file\n'
    occupied.write_bytes(occupied_bytes)
    try:build(folder/'order-0-0/source.tex',engine=engine,output_dir=collision)
    except RuntimeError as error:
        collision_evidence=failure_evidence(folder/'order-0-0',error,'existing generated filename has different bytes',engine)
    else:raise AssertionError('Existing different generated file was silently replaced')
    assert occupied.read_bytes()==occupied_bytes;negative.append('occupied-generated-file-preserved')
    collision_evidence['name']='occupied-generated-file-preserved';negative_evidence.append(collision_evidence)
    assert fingerprint()[0]==digest,'Source changed during native TeX acceptance'
    receipt={'schema_version':1,'engine':engine,'source_digest':digest,'source_files':source,'runtime':{'pypdf':pypdf.__version__,'Pillow':PIL.__version__,
        executable:subprocess.check_output([executable,'--version'],text=True).splitlines()[0]},
        'book_pages':len(reader.pages),'unique_generations':trace['unique_generations'],'physical_views':trace['physical_views'],
        'measurements':measured,'irregular_protected_ink':ink,'inline_pages':inline_pages,'searchable_micrography':True,
        'searchable_initial_folio':True,'spread_instance':left['instance_sha256'],'load_orders':load_order,'negative_cases':negative,
        'negative_evidence':negative_evidence,
        'initial_passes':len(passes),'auxiliary_state':initial_state,'pattern_receipt_converged':True,'discarded_shipout_checked':True,
        'compiler_command_policy':executable+' -no-shell-escape -halt-on-error -interaction=nonstopmode -recorder',
        'outputs':{'book.pdf':hashlib.sha256(pdf.read_bytes()).hexdigest(),'book-patterns.json':hashlib.sha256(trace_path.read_bytes()).hexdigest()}}
    (folder/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf8')
    print('Native common-pattern TeX consumer passed',engine,len(reader.pages),'pages,',len(measured),'physical placements,',len(load_order),'load orders and',len(negative),'failure cases')
    return folder,receipt


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--engine',choices=('lua','xe'),default='lua')
    main(parser.parse_args().engine)

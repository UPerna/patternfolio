"""Independent physical-document, exact crop, route and raster acceptance QA."""
import argparse
from fractions import Fraction as F
from decimal import Decimal,localcontext
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image, ImageChops, ImageStat

ROOT=Path(__file__).resolve().parents[1]
NS={'s':'http://www.w3.org/2000/svg'}
def run(args):return subprocess.run(args,check=True,capture_output=True).stdout
def near(actual,expected):assert abs(float(actual)-float(expected))<1e-10,(actual,str(expected))
def box_interval(a,b,box):
    low,high=F(0),F(1)
    for axis in (0,1):
        delta=b[axis]-a[axis]
        if delta==0:
            if a[axis]<box[axis] or a[axis]>box[axis+2]:return None
        else:
            t,u=(box[axis]-a[axis])/delta,(box[axis+2]-a[axis])/delta
            low,high=max(low,min(t,u)),min(high,max(t,u))
            if low>high:return None
    return low,high
def check_route(route):
    points=[tuple(F(c) for c in p) for p in route['points']];clear=F(route['clearance'])
    region=tuple(map(F,(0,0,6,20)));obstacle=(F(2)-clear,F(7)-clear,F(4)+clear,F(11)+clear)
    assert points[0]==(F(3),F(1)) and points[-1]==(F(3),F(18))
    for a,b in zip(points,points[1:]):
        assert box_interval(a,b,region)==(F(0),F(1)),'Route leaves permitted rectangle'
        assert box_interval(a,b,obstacle) is None,'Route violates exact whole-segment exclusion clearance'
    return len(points)-1
def parsed_world_paths(plan,origin):
    output={}
    for op in plan['operations']:
        if op['op']!='path':continue
        a,b,c,d,x,y=op['transform'];commands=[]
        for cmd in op['commands']:
            value=[cmd[0]]
            for i in range(1,len(cmd),2):value.extend([a*cmd[i]+c*cmd[i+1]+x+origin[0],b*cmd[i]+d*cmd[i+1]+y+origin[1]])
            commands.append(value)
        assert op['semantic_ref'] not in output,'Global tile edge/cell painted twice'
        output[op['semantic_ref']]={'commands':commands,'paint':op['paint']}
    return output
def inspect(folder,existing):
    reports=sorted(folder.glob('receipt-Lua-*.json'));assert reports,'Run plannercheck first'
    r=json.loads(reports[0].read_text())
    for path in reports[1:]:
        other=json.loads(path.read_text());assert other['outputs']==r['outputs'] and other['book_pdf']==r['book_pdf'],'Shared drawing bytes differ across Lua runtimes'
        assert [x['stats'] for x in other['legacy']]==[x['stats'] for x in r['legacy']],'Legacy adaptive generation differs across Lua runtimes'
    assert r['generator_calls']==1,'Viewport changes regenerated the construction'
    replay=r['recipe_replay'];assert r['recipe_generator_calls']>=2,'Recipe replay must actually exercise construction'
    assert replay['fixed_build']['status']=='complete' and replay['rejected_build']['status']=='failed' and not replay['rejected_build']['outputs']
    assert replay['fixed_keys']['structure']==replay['cropped_keys']['structure']==replay['masked_keys']['structure']
    assert replay['fixed_keys']['view']!=replay['cropped_keys']['view'] and replay['fixed_keys']['view']!=replay['masked_keys']['view']
    assert replay['adaptive_keys'][0]['structure']!=replay['adaptive_keys'][1]['structure']
    loaded={}
    for key,item in replay['files'].items():
        data=(ROOT/item['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==item['sha256'];loaded[key]=json.loads(data)
    assert replay['files']['instance']['sha256']==r['instance_sha256']==replay['fixed_build']['outputs'][0]['sha256']
    assert replay['files']['scene']['sha256']==replay['fixed_build']['outputs'][1]['sha256']
    assert {o['semantic_ref'] for o in loaded['scene']['operations'] if o.get('semantic_ref','').startswith('cell/')}=={'cell/7/3','cell/7/4'},'Saved full-tile recipe lost actual cell selection'
    assert loaded['recipe']['view']['extensions']['document_planning']['schema_version']==1
    for key,expected in [('adaptive_a',F('5.4')),('adaptive_b',F('5.6'))]:near(loaded[key]['structures']['growth']['nodes'][0]['point'][0],expected)
    for item in r['source']:assert hashlib.sha256((ROOT/item['path']).read_bytes().replace(b'\r\n',b'\n')).hexdigest()==item['sha256'],'Stale planner source evidence'
    for case in r['numeric_comparisons']:
        exact=F(case['numerator'],case['denominator']);bound=F(case['bound']);expected=(exact>bound)-(exact<bound)
        assert case['comparison']==expected,('Rational coordinate classification',case,expected)
    # Independently written decimal/Fraction expectations, not derived Lua fields.
    p=r['documents']['panel']['pages'][0]
    panel_content=(F('0.25')+F('0.4')+F('0.2')+F('0.1'),F('0.25')+F('0.4')-F('0.1'),F('3.75')-F('0.4')+F('0.1'),F('2.75')-F('0.4')-F('0.1'))
    for a,e in zip(p['content'],panel_content):near(a,e)
    for a,e in zip(p['anchors'][0]['point'],map(F,('5.4','3.35'))):near(a,e)
    left,right=r['documents']['book']['pages']
    for a,e in zip(left['content'],map(F,('0.7','0.65','3','2.25'))):near(a,e)
    for a,e in zip(right['content'],map(F,('1','0.75','3.3','2.35'))):near(a,e)
    assert left['inner_side']=='right' and right['inner_side']=='left'
    for a,e in zip(left['protected_regions'][0]['bounds'],map(F,('0.9','0.95','1.6','1.75'))):near(a,e)
    assert r['generation_request']['specification']['document']['bounds']==[1,0.5,13,7.5]
    assert not r['generation_request']['specification']['document']['protected_regions'],'Fixed frame reservations changed the construction request'
    assert r['adaptive_request']['generation_region']=='content'
    for actual,expected in zip(r['adaptive_request']['specification']['document']['bounds'],map(F,('5.2','3.05','7.7','4.75'))):near(actual,expected)
    route_segments=check_route(r['route'])
    assert r['positioned_text_measurement']['minimum_text_size']==0.3
    with localcontext() as ctx:
        ctx.prec=80
        for case in r['affine_measurements']:
            a,b,c,d=[Decimal.from_float(float(v)) for v in case['matrix'][:4]]
            aa,bb,ab=a*a+b*b,c*c+d*d,a*c+b*d
            eigen=(aa+bb-((aa-bb)**2+4*ab*ab).sqrt())/2
            true_size=Decimal.from_float(float(case['size']))*eigen.sqrt()
            measured=case['measurement'];low=Decimal.from_float(float(measured['minimum_text_size_lower_bound']));high=Decimal.from_float(float(measured['minimum_text_size_upper_bound']))
            # Exact diagonal input and multiplication can round at most one
            # binary64 ulp. General affine bounds retain the larger guard.
            guard=Decimal('1e-16')*max(abs(true_size),Decimal(1))
            assert low-guard<=true_size<=high+guard,'Affine physical text measurement excludes high-precision singular value'
    assert r['closed_strand_view'][0]['closed'] and r['closed_strand_view'][0]['view_clip_is_not_a_break']
    assert r['blocked_route']['status']=='rejected' and len(r['blocked_route']['details']['original_points'])==69
    images={};metrics=[];plans={}
    expected_sizes={'panel':(F('3.5'),F('2.5')),'panel-full':(F('3.5'),F('2.5')),'verso':(F(4),F(3)),'recto':(F(4),F(3)),'overlap-a':(F(4),F(2)),'overlap-b':(F(4),F(2))}
    for item in r['outputs']:
        name=item['name'];width,height=expected_sizes[name];dims=round(width*60),round(height*60)
        for key in ('pdf','svg','plan'):
            out=item[key];assert hashlib.sha256((ROOT/out['path']).read_bytes()).hexdigest()==out['sha256'],'Output digest mismatch'
        info=run(['pdfinfo',str(folder/(name+'.pdf'))]).decode()
        size=re.search(r'Page size:\s+([\d.]+) x ([\d.]+) pts',info);assert size
        assert abs(float(size[1])-float(width*72/F('2.54')))<0.02 and abs(float(size[2])-float(height*72/F('2.54')))<0.02
        svg=ET.parse(folder/(name+'.svg')).getroot()
        near(svg.attrib['width'][:-2],width);near(svg.attrib['height'][:-2],height)
        assert svg.attrib['width'].endswith('cm') and svg.attrib['height'].endswith('cm') and not svg.findall('.//s:image',NS)
        if not existing:
            run(['pdftoppm','-scale-to-x',str(dims[0]),'-scale-to-y',str(dims[1]),'-png','-singlefile',str(folder/(name+'.pdf')),str(folder/(name+'-pdf'))])
            run(['inkscape',str(folder/(name+'.svg')),'--export-area-page','--export-background=white','--export-background-opacity=1',f'--export-width={dims[0]}',f'--export-height={dims[1]}',f'--export-filename={folder/(name+"-svg.png")}'])
        pairs={kind:Image.open(folder/(name+'-'+kind+'.png')).convert('RGB') for kind in ('pdf','svg')}
        assert all(im.size==dims for im in pairs.values())
        error=sum(ImageStat.Stat(ImageChops.difference(pairs['pdf'],pairs['svg'])).mean)/3/255
        assert error<0.04,('Independent raster mismatch',name,error)
        plan=json.loads((folder/(name+'.plan')).read_text());plans[name]=plan;images[name]=pairs
        b=plan['bounds'];protected=[]
        for region in item['decisions'].get('selection',{}).get('masked_edges',[]):assert region['kind']=='protected_view_mask_not_topological_boundary'
        # Read the original physical page reservations, convert only the crop's
        # lower-left offset into image coordinates, and exclude a2px AA edge.
        page=r['documents']['panel']['pages'][0] if name.startswith('panel') else left if name=='verso' else right if name=='recto' else None
        for reserve in page['protected_regions'] if page else []:
            a=reserve['bounds'];roi=(math.ceil((a[0]-b[0])*60)+2,math.ceil((b[3]-a[3])*60)+2,math.floor((a[2]-b[0])*60)-2,math.floor((b[3]-a[1])*60)-2)
            assert roi[0]<roi[2] and roi[1]<roi[3]
            minima=[min(low for low,high in im.crop(roi).getextrema()) for im in pairs.values()]
            assert min(minima)>=254,('Protected actual ink',name,roi,minima)
            protected.append({'physical_bounds':a,'pixel_box':roi,'minimum_channel':minima})
        metrics.append({'name':name,'dimensions':dims,'mean_absolute_error':error,'protected_ink':protected})
    # Pull both views back into the world: stable semantic IDs, geometry and
    # paint must agree. The independently rasterized common interior also agrees.
    a=parsed_world_paths(plans['overlap-a'],(3,3));b=parsed_world_paths(plans['overlap-b'],(5,3));common=set(a)&set(b)
    assert common and all(a[key]==b[key] for key in common),'World anchored geometry/paint differs in overlap'
    overlap_errors={}
    for kind in ('pdf','svg'):
        aa=images['overlap-a'][kind].crop((122,2,238,118));bb=images['overlap-b'][kind].crop((2,2,118,118))
        extrema=ImageChops.difference(aa,bb).getextrema();maximum=max(high for low,high in extrema)
        assert maximum<=1,('Actual overlap pixels differ',kind,maximum);overlap_errors[kind]=maximum
    # Explicit physical source-edge probe: worldx5 becomes0.5cm from the panel's
    # trimmed output left edge, not0.75cm and not a doubly shifted position.
    for kind in ('pdf','svg'):
        im=images['panel'][kind];pixel=im.getpixel((30,33));assert max(pixel)<100,('World/page/trim origin probe',kind,pixel)
        assert min(images['panel-full'][kind].getpixel((135,27)))>=254,'Full-tile policy retained a partial/excluded tile'
        assert max(images['panel'][kind].getpixel((135,27)))<240,'Clipped-tile control region is empty'
    out=r['book_pdf'];assert hashlib.sha256((ROOT/out['path']).read_bytes()).hexdigest()==out['sha256']
    info=run(['pdfinfo',str(folder/'book.pdf')]).decode();assert re.search(r'Pages:\s+2\b',info),'Facing document must have two actual PDF pages'
    run(['pdftoppm','-scale-to-x','240','-scale-to-y','180','-png',str(folder/'book.pdf'),str(folder/'book')])
    for index,name in enumerate(('verso','recto'),1):
        im=Image.open(folder/f'book-{index}.png').convert('RGB');assert ImageChops.difference(im,images[name]['pdf']).getbbox() is None,'Multi-page container moved page geometry'
    # Actual host scaled points are checked with independent rational TeX units.
    dims=r['legacy_host']['dimensions_sp'];factor=F(254,100)/F(7227,100)/65536
    cm=lambda key:F(dims[key])*factor
    host_checks=0
    for case in r['legacy_host']['cases']:
        number,side=case['number'],case['side'];actual_left=F('2.54')+cm('evensidemargin' if number%2==0 else 'oddsidemargin')+cm('hoffset')
        actual_right=actual_left+cm('textwidth');recto=number%2==1
        mirror=side=='right' or side=='outer' and recto or side=='inner' and not recto
        expected_left=cm('paperwidth')-actual_right if mirror else actual_left
        expected_right=cm('paperwidth')-actual_left if mirror else actual_right
        g=case['geometry'];assert g['mirror']==mirror
        host_page=case['document']['pages'][0];assert host_page['binding_offset']==0 and host_page['offset']==[0,0],'Host binding/offset applied twice'
        for actual,expected in zip(host_page['content'],(actual_left,cm('paperheight')-F('2.54')-cm('topmargin')-cm('headheight')-cm('headsep')-cm('voffset')-cm('textheight'),actual_right,cm('paperheight')-F('2.54')-cm('topmargin')-cm('headheight')-cm('headsep')-cm('voffset'))):near(actual,expected)
        for key,expected in {'pw':cm('paperwidth'),'ph':cm('paperheight'),'actual_left':actual_left,'actual_right':actual_right,'textleft':expected_left,'textright':expected_right,'colright':expected_left-F('0.15')-F('0.25')}.items():near(g[key],expected)
        top=cm('paperheight')-F('2.54')-cm('topmargin')-cm('headheight')-cm('headsep')-cm('voffset')
        near(g['ytop'],top);near(g['ybot'],top-cm('textheight'));near(g['footy'],top-cm('textheight')-cm('footskip'))
        expected=[cm('paperwidth')-3,F(8),cm('paperwidth')-1,F(12)] if mirror else [F(1),F(8),F(3),F(12)]
        for actual,value in zip(g['reserves'][0],expected):near(actual,value)
        host_checks+=1
    assert host_checks==8
    assert len(r['legacy'])>=2 and r['legacy'][1]['stats']['cells']<r['legacy'][0]['stats']['cells'] and r['legacy'][1]['stats']['skipped']>0,'Flowers did not actually adapt before clipping'
    legacy_checks=[]
    for item in r['legacy']:
        pdf=ROOT/item['pdf']['path'];assert hashlib.sha256(pdf.read_bytes()).hexdigest()==item['pdf']['sha256']
        stem=pdf.with_suffix('');run(['pdftoppm','-r','65','-png','-singlefile',str(pdf),str(stem)])
        im=Image.open(Path(str(stem)+'.png')).convert('RGB');assert im.getextrema()[0][0]<150,'Legacy floral output is empty'
        protected=[];pixels_per_cm=65/F('2.54')
        for a in item['physical_reservations']:
            roi=(math.ceil(a[0]*pixels_per_cm)+2,math.ceil((float(cm('paperheight'))-a[3])*pixels_per_cm)+2,math.floor(a[2]*pixels_per_cm)-2,math.floor((float(cm('paperheight'))-a[1])*pixels_per_cm)-2)
            minimum=min(low for low,high in im.crop(roi).getextrema());assert minimum>=254,('Actual adaptive floral protected ink',roi,minimum)
            protected.append({'physical_bounds':a,'pixel_box':roi,'minimum_channel':minimum})
        legacy_checks.append({'kind':item['kind'],'stats':item['stats'],'protected_ink':protected,'pdf_sha256':item['pdf']['sha256']})
    result={'stage':'07','source_digest':r['source_digest'],'status':'document_view_oracle_passed','rasterizers':'local librsvg/Poppler' if existing else 'Inkscape/Poppler',
      'exact_rational_comparisons':len(r['numeric_comparisons']),'route_segments':route_segments,'world_overlap_semantic_objects':len(common),'overlap_max_channel_error':overlap_errors,'fixtures':metrics,'book_pages':2,
      'independent_host_geometry_cases':host_checks,'affine_decimal_comparisons':len(r['affine_measurements']),'recipe_replay':'actual saved source/scene/BuildRecord bytes verified; fixed view keys separate from adaptive construction keys','legacy_adaptation':legacy_checks}
    destination=folder/('oracle-local.json' if existing else 'oracle.json');encoded=json.dumps(result,indent=2)+'\n'
    if destination.exists():assert destination.read_text()==encoded,'Oracle evidence differs; preserve and investigate'
    else:destination.write_text(encoded)
    print('planner_oracle: exact comparisons, actual standalone/two-page coordinates, world overlap and strict protected ink passed',r['source_digest'])
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--directory',type=Path);p.add_argument('--existing-rasters',action='store_true');args=p.parse_args()
    folders=[args.directory] if args.directory else sorted((ROOT/'build/planner').glob('*'));assert folders,'Run plannercheck first'
    for folder in folders:inspect(folder,args.existing_rasters)

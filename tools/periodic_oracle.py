"""Independent exact lattice proofs, actual scene and overlap QA for stage09."""
import argparse
from collections import Counter, defaultdict
from functools import cmp_to_key
from pathlib import Path
import hashlib
import json
import math
import re
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageStat

ROOT=Path(__file__).resolve().parents[1]
AREAS={
 'square':{'s':(72,0)},'triangular':{'up':(36,0),'down':(36,0)},
 'hexagonal':{'h':(72,0)},'4.8.8':{'oct':(-144,144),'gap':(216,-144)},
 '4.6.12':{'d':(0,24),'s0':(-24,16),'s1':(-24,16),'s2':(-24,16),'h0':(72,-36),'h1':(72,-36)},
}
VERTEX_TYPES={'square':[4]*4,'triangular':[3]*6,'hexagonal':[6]*3,'4.8.8':[4,8,8],'4.6.12':[4,6,12]}
CLASSES={'square':2,'triangular':3,'hexagonal':3,'4.8.8':6,'4.6.12':18}
def load(p):return json.loads(p.read_text(encoding='utf8'))
def hash_file(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pairadd(a,b):return(a[0]+b[0],a[1]+b[1])
def pairsub(a,b):return(a[0]-b[0],a[1]-b[1])
def mul(a,b,d):return(a[0]*b[0]+d*a[1]*b[1],a[0]*b[1]+a[1]*b[0])
def cross(a,b,d):return pairsub(mul(a[:2],b[2:],d),mul(a[2:],b[:2],d))
def qsub(a,b):return tuple(x-y for x,y in zip(a,b))
def shift(p,i,j):return(p[0]+6*i,p[1],p[2]+6*j,p[3])
def qsign(q,d):
 a,b=q
 if a>=0 and b>=0:return int(a!=0 or b!=0)
 if a<=0 and b<=0:return -1
 positive=a*a>d*b*b if a>0 else d*b*b>a*a
 return 1 if positive else -1
def ring(points):return list(zip(points,points[1:]+points[:1]))
def quotient(p):return(p[0]%6,p[1],p[2]%6,p[3])
def sat(a,b,d):
 order=cmp_to_key(lambda x,y:qsign(pairsub(x,y),d))
 for x,y in ring(a)+ring(b):
  direction=qsub(y,x)
  p=[cross(direction,v,d)for v in a];q=[cross(direction,v,d)for v in b]
  if qsign(pairsub(max(p,key=order),min(q,key=order)),d)<=0 or qsign(pairsub(max(q,key=order),min(p,key=order)),d)<=0:return True
 return False
def prove_templates(templates):
 stats={}
 for t in templates:
  name=t['id'];d=t['radicand'];faces=t['faces'];edge_classes=defaultdict(list);stars=defaultdict(list);areas={}
  all_vertices=[v for f in faces for v in f['vertices']]
  for axis in (0,2):
   order=cmp_to_key(lambda x,y:qsign(pairsub(x,y),d))
   values=[v[axis:axis+2]for v in all_vertices]
   assert qsign(pairsub(pairsub(max(values,key=order),min(values,key=order)),(12,0)),d)<=0
  for f in faces:
   vertices=f['vertices'];area=(0,0)
   for a,b in ring(vertices):
    area=pairadd(area,cross(a,b,d));stars[quotient(a)].append(len(vertices))
    directed=(quotient(a),qsub(b,a));reverse=(quotient(b),qsub(a,b))
    edge_classes[min(directed,reverse)].append(directed)
    assert qsign(cross(qsub(b,a),qsub(f['center'],a),d),d)>0
   areas[f['id']]=area
  assert areas==AREAS[name],(name,areas)
  assert all(sorted(s)==VERTEX_TYPES[name]for s in stars.values()),(name,stars)
  assert len(edge_classes)==CLASSES[name]and all(len(p)==2 and p[0]!=p[1]for p in edge_classes.values())
  checks=0
  for a in faces:
   for b in faces:
    for i in range(-2,3):
     for j in range(-2,3):
      if a is b and i==j==0:continue
      assert sat(a['vertices'],[shift(p,i,j)for p in b['vertices']],d),(name,a['id'],b['id'],i,j)
      checks+=1
  stats[name]={'unit_area':1,'paired_edges':len(edge_classes),'vertex_types':VERTEX_TYPES[name],'potential_overlaps_excluded':checks}
 return stats
def mm(a,b):
 return(a[0]*b[0]+a[1]*b[2],a[0]*b[1]+a[1]*b[3],a[2]*b[0]+a[3]*b[2],a[2]*b[1]+a[3]*b[3])
def groups_check(groups):
 i=(1,0,0,1);half=(-1,0,0,-1);q=(0,-1,1,0)
 # General positions in the 120-degree IUCr chart, conjugated to this 60-degree chart.
 old=[i,(0,-1,1,-1),(-1,1,-1,0),half,(0,1,-1,1),(1,-1,1,0)]
 c=(1,1,0,1);cinv=(1,-1,0,1)
 six={mm(mm(cinv,a),c)for a in old};mirror={mm(mm(cinv,mm(a,(1,-1,0,-1))),c)for a in old}
 four={i,q,half,(0,1,-1,0)}
 expected={'p1':{i},'p2':{i,half},'p3':{mm(mm(cinv,a),c)for a in old[:3]},
           'p4':four,'p4m':four|{mm(a,(1,0,0,-1))for a in four},'p6':six,'p6m':six|mirror}
 assert {g['id']for g in groups}==set(expected)
 for g in groups:
  got={tuple(x['matrix'])for x in g['operations']};assert got==expected[g['id']]
  assert all(mm(a,b)in got for a in got for b in got)
  for op in g['operations']:
   a,b,c,d=op['matrix'];assert a*d-b*c==op['orientation']
 return {g['id']:len(g['operations'])for g in groups}
def check_patch(x,template):
 p=x['extensions']['periodic'];m=p['matrix'];d=p['radicand'];t=x['structures']['tiling']
 vs={v['id']:v for v in t['vertices']};es={e['id']:e for e in t['edges']}
 faces={f['id']:f for f in template['faces']};step=p['step_cm']
 a=(m[0],m[1]);b=(m[2],m[3]);assert abs(math.hypot(*a)-step)<1e-12 and abs(math.hypot(*b)-step)<1e-12
 assert abs(sum(x*y for x,y in zip(a,b))-(step*step/2 if p['lattice']=='hexagonal'else 0))<1e-12
 assert m[0]*m[3]-m[1]*m[2]>0
 for v in vs.values():
  u0,u1,v0,v1=v['lattice'];u=(u0+math.sqrt(d)*u1)/6;w=(v0+math.sqrt(d)*v1)/6
  assert math.dist(v['point'],(m[0]*u+m[2]*w+m[4],m[1]*u+m[3]*w+m[5]))<1e-11
 used=defaultdict(list);edge_lengths={'square':1,'triangular':1,'hexagonal':1/math.sqrt(3),'4.8.8':math.sqrt(2)-1,'4.6.12':(3-math.sqrt(3))/6}
 for c in t['cells']:
  f=faces[c['template']];points=[]
  for use in c['boundary']:
   e=es[use['edge']];used[e['id']].append((c['id'],use['reversed']))
   points.append(vs[e['to']if use['reversed']else e['from']]['lattice'])
   assert use['port_ref']==e['midpoint']['id']
  assert points==[list(shift(v,*c['address']))for v in f['vertices']]
  assert c['chirality']==1 and not c['isometry']['reflection']
 for e in es.values():
  a,b=vs[e['from']],vs[e['to']];port=e['midpoint'];incidence=used[e['id']]
  assert abs(math.dist(a['point'],b['point'])-step*edge_lengths[p['template']])<1e-11
  assert port['lattice']==[x+y for x,y in zip(a['lattice'],b['lattice'])]and port['lattice_denominator']==12
  assert math.dist(port['point'],[(x+y)/2 for x,y in zip(a['point'],b['point'])])<1e-11
  assert e['global_cells']==sorted(e['global_cells'])and e['global_owner']==e['global_cells'][0]
  if len(incidence)==2:
   assert e['role']=='interior'and sorted(i[0]for i in incidence)==e['global_cells']and incidence[0][1]!=incidence[1][1]
  else:assert len(incidence)==1 and e['role']=='patch_boundary'and e['owner']==incidence[0][0]
 return {'vertices':len(vs),'edges':len(es),'cells':len(t['cells'])}
def checked_pixels(folder,fixtures,existing):
 pictures={};reports=[]
 for case in fixtures:
  name=case['name'];width,height=case['size'];w,h=round(width*60),round(height*60)
  svg=ET.parse(folder/(name+'.svg')).getroot()
  assert svg.attrib['width'].endswith('cm')and svg.attrib['height'].endswith('cm')
  assert abs(float(svg.attrib['width'][:-2])-width)<1e-12 and abs(float(svg.attrib['height'][:-2])-height)<1e-12
  assert not any(node.tag.endswith('}image')for node in svg.iter())
  info=subprocess.check_output(['pdfinfo',str(folder/(name+'.pdf'))],text=True)
  sizes=re.search(r'Page size:\s*([\d.]+) x ([\d.]+) pts',info);assert sizes
  assert abs(float(sizes[1])-width*72/2.54)<0.02 and abs(float(sizes[2])-height*72/2.54)<0.02
  pdf_png=folder/(name+'-pdf.png');svg_png=folder/(name+'-svg.png')
  if not existing or not pdf_png.exists():
   subprocess.run(['pdftoppm','-scale-to-x',str(w),'-scale-to-y',str(h),'-png','-singlefile',str(folder/(name+'.pdf')),str(folder/(name+'-pdf'))],check=True,capture_output=True)
  if not existing:
   subprocess.run(['inkscape',str(folder/(name+'.svg')),'--export-area-page','--export-width='+str(w),'--export-height='+str(h),'--export-filename='+str(svg_png)],check=True,capture_output=True)
  pdf=Image.open(pdf_png).convert('RGB');vector=Image.open(svg_png).convert('RGB')
  assert pdf.size==vector.size==(w,h)
  assert all(ImageChops.difference(im,Image.new('RGB',(w,h),'white')).getbbox()for im in [pdf,vector])
  mae=sum(ImageStat.Stat(ImageChops.difference(pdf,vector)).mean)/765
  assert mae<0.04,(name,mae)
  pictures[name]=(pdf,vector);reports.append({'fixture':name,'pixels':[w,h],'mae':mae})
  if name=='masked-full':
   for im in (pdf,vector):
    roi=im.crop((77,77,109,112));assert all(lo==255 for lo,_ in roi.getextrema()),'protected callout has ink'
 overlap={}
 for kind,i in [('pdf',0),('svg',1)]:
  left=pictures['4.6.12'][i];right=pictures['4.6.12-overlap'][i];w,h=left.size
  delta=ImageChops.difference(left.crop((86,2,w-2,h-2)),right.crop((2,2,w-86,h-2)))
  peak=max(hi for lo,hi in delta.getextrema())
  differing=sum(1 for p in delta.getdata()if any(p))
  # Different clipping surfaces can affect subpixel coverage. Retain this
  # diagnostic alongside the exact same-world-window acceptance check.
  overlap[kind]={'different_viewports_peak':peak,'different_viewports_changed_pixels':differing}
  common=ImageChops.difference(pictures['common-a'][i],pictures['common-b'][i])
  assert common.getbbox()is None,(kind,'same physical viewport differs')
  overlap[kind]['same_world_window_peak']=0
 return reports,overlap
def common_world_paint(folder):
 a=load(folder/'4.6.12.plan');b=load(folder/'4.6.12-overlap.plan')
 def paths(plan):
  records={}
  for op in plan['operations']:
   if op['op']!='path':continue
   key=(op['semantic_ref'],json.dumps(op['paint'],sort_keys=True))
   assert key not in records
   records[key]=op['commands']
  return records
 x,y=paths(a),paths(b);shared=x.keys()&y.keys()
 assert shared and all(x[k]==y[k]for k in shared),'common world paint coordinates differ'
 def interior(records):
  out=set()
  for k,commands in records.items():
   pts=[q[1:]for q in commands if q[0]in ('M','L')]
   assert pts
   xx,yy=zip(*pts)
   if max(xx)>-0.78 and min(xx)<0.98 and max(yy)>-1.38 and min(yy)<1.38:out.add(k)
  return out
 assert interior(x)==interior(y),'an interior world paint operation is missing'
 for suffix in ['pdf','svg','plan']:
  assert (folder/('common-a.'+suffix)).read_bytes()==(folder/('common-b.'+suffix)).read_bytes()
 return len(shared)
def inspect(folder,existing):
 receipts=sorted(folder.glob('receipt-*.json'))
 if not receipts:return False
 r=load(receipts[0]);src=[{'path':e['path'],'sha256':hashlib.sha256((ROOT/e['path']).read_bytes().replace(b'\r\n',b'\n')).hexdigest()}for e in r['source']]
 if src!=r['source']:return False
 assert hashlib.sha256(json.dumps(src,sort_keys=True,separators=(',',':')).encode()).hexdigest()==r['source_digest']
 for item in receipts:
  rr=load(item);assert rr['outputs']==r['outputs']and rr['recipe']['status']=='complete'
 for name,sha in r['outputs'].items():assert hash_file(folder/name)==sha,name
 templates={t['id']:t for t in load(folder/'templates.json')}
 proofs=prove_templates(templates.values());groups=groups_check(load(folder/'groups.json'));patches={}
 for case in r['fixtures']:
  name=case['name'];x=load(folder/case.get('instance',name+'.instance'));patches[name]=check_patch(x,templates[x['extensions']['periodic']['template']])
 first=load(folder/'4.6.12.instance');second=load(folder/'4.6.12-overlap.instance')
 for kind in ['vertices','edges','cells']:
  a={v['id']:v for v in first['structures']['tiling'][kind]};b={v['id']:v for v in second['structures']['tiling'][kind]}
  shared=a.keys()&b.keys();assert len(shared)==r['shared'][kind]
  for k in shared:
   if kind=='edges':assert a[k]['global_owner']==b[k]['global_owner']and a[k]['midpoint']==b[k]['midpoint']
   else:assert a[k]==b[k]
 shifted=load(folder/'translated.instance');dx,dy=r['translation_vector']
 shifted_vertices={tuple(v['lattice']):v for v in shifted['structures']['tiling']['vertices']}
 for v in first['structures']['tiling']['vertices']:
  p=shifted_vertices[shift(v['lattice'],2,-1)]['point'];assert math.dist(p,[v['point'][0]+dx,v['point'][1]+dy])<1e-11
 common_paths=common_world_paint(folder)
 raster,overlap=checked_pixels(folder,r['fixtures'],existing)
 report={'stage':'09','source_digest':r['source_digest'],'proofs':proofs,'wallpaper_operations':groups,'patches':patches,'shared':r['shared'],
  'rasterizers':'local Poppler/librsvg'if existing else'Inkscape/Poppler','images':raster,'world_paths_equal':common_paths,'overlap_raster_comparison':overlap}
 (folder/('oracle-local.json'if existing else'oracle.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
 print('periodic_oracle: five exact template quotients, seven group actions, actual rotated patches, port seams and world raster overlap passed',r['source_digest'])
 return True
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',type=Path);parser.add_argument('--existing-rasters',action='store_true')
 args=parser.parse_args();paths=[args.directory]if args.directory else sorted((ROOT/'build/periodic').glob('*'))
 assert sum(inspect(p,args.existing_rasters)for p in paths),'no current-source periodic receipts'
if __name__=='__main__':main()

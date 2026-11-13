"""Stage33 independent arithmetic/graph checks and checking-path corruptions.

Reuses separately implemented Python/Decimal source-method auditors, never the
Lua generator's tables. This is independent checking code, not another reviewer.
"""
import argparse,hashlib,json,math
from collections import Counter
from decimal import getcontext
from fractions import Fraction
from pathlib import Path
import penrose_oracle as penrose
import spectre_oracle as spectre
import micrography_oracle as micro

def read(p):return json.loads(p.read_text(encoding='utf8'))
def sign_area(points):
 p=[tuple(map(Fraction,v))for v in points]
 return sum(a[0]*b[1]-a[1]*b[0]for a,b in zip(p,p[1:]+p[:1]))

def periodic(x):
 t=x['structures']['tiling'];vs={v['id']:v for v in t['vertices']};es={e['id']:e for e in t['edges']};cells=t['cells'];seen=set();usage=Counter()
 assert len(vs)==len(t['vertices'])and len(es)==len(t['edges'])
 for cell in cells:
  assert cell['id']not in seen,'duplicate cell';seen.add(cell['id']);segments=[]
  for boundary in cell['boundary']:
   edge=es[boundary['edge']];a,b=edge['from'],edge['to'];usage[edge['id']]+=1
   if boundary['reversed']:a,b=b,a
   assert a in vs and b in vs and a!=b;segments.append((a,b))
  assert all(b==segments[(i+1)%len(segments)][0]for i,(a,b)in enumerate(segments)),'open cell'
  assert sign_area([vs[a]['point']for a,b in segments])!=0,'degenerate cell'
 assert all(n<=2 for n in usage.values()),'nonmanifold edge'
 return {'cells':len(seen),'edges':len(es),'vertices':len(vs),'rational_nonzero_polygon_area':True,'closed_boundaries':True}

def micrography(x):
 e=x['extensions']['micrography'];f=e['field'];points=f['points'];line_indices=[]
 for tri in f['triangles']:
  assert len(tri)==3 and all(type(i)is int and 1<=i<=len(points)for i in tri),'triangle reference'
  assert sign_area([points[i-1]for i in tri])>0,'triangle orientation'
 for position in e['positions']:
  i=position['line'];assert type(i)is int and 1<=i<=len(e['streamlines']),'line reference';line_indices.append(i)
  assert all(type(a)is int and type(b)is int and 1<=a<=b<=len(e['clusters'])for a,b in position['spans']),'grapheme span'
 assert line_indices==sorted(set(line_indices)),'line ordering'
 return {'independent_signed_label_optimization':micro.field_audit(e),'independent_layout_geometry':micro.layout_audit(x),'exact_triangle_orientation':len(f['triangles']),'line_references':len(line_indices)}

def main():
 p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,default=Path('build/adversarial'));args=p.parse_args();d=args.directory
 methods={'periodic':periodic,'penrose':lambda x:penrose.audit(x)[0],'micrography':micrography}
 getcontext().prec=76
 x=read(d/'spectre-instance.json');q=x['extensions']['spectre']['request'];reference=spectre.reference(q['depth'],q['root']);geometry=spectre.root_complex(reference[0]);methods['spectre']=lambda x:spectre.audit(x,reference,geometry)
 results={name:method(read(d/(name+'-instance.json')))for name,method in methods.items()}
 detected=[]
 for file in sorted(d.glob('*-corruption.json')):
  v=read(file);name=file.name.split('-',1)[0]
  try:methods[name](v['instance'])
  except (AssertionError,IndexError,KeyError,TypeError,ValueError)as error:detected.append({'case':file.name,'diagnostic':str(error)[:220]or type(error).__name__,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
  else:raise AssertionError('Independent checker accepted corruption:'+file.name)
 assert len(detected)==8,('Missing fixed corruption corpus',len(detected))
 hashes={name:hashlib.sha256((d/(name+'-instance.json')).read_bytes()).hexdigest()for name in methods}
 out={'status':'passed','scope':'Single-agent independent arithmetic/checking code; not independent human or swarm review','precision_digits':getcontext().prec,'instance_sha256':hashes,'results':results,'controlled_corruptions_detected':detected,'test_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
 (d/'independent-oracle.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf8');print('Independent adversarial oracle:4 families and8 controlled corruptions passed')
if __name__=='__main__':main()

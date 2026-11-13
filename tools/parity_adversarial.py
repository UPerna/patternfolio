"""Independent checking-path controls; exact labels, continuous coordinates only."""
import argparse,hashlib,json,sys
from pathlib import Path
from browser_parity import Comparator

def audit():
 rows=[]
 exact={
 'micrography':('positions/0/line','positions/0/spans/0/0','field/triangles/0/0','field/labels/samples/0/label','field/labels/samples/0/node','field/labels/edges/0/0','field/iterations','field/labels/mask','field/unknown'),
 'decobrush':('field/matches/0/piece','field/matches/0/first','field/matches/0/last','field/matches/0/mesh/faces/0/0','field/seams/0/indices/0','field/seams/0/certificate/flow','field/grid/0/source/piece','field/width','field/unknown')}
 for family,paths in exact.items():
  for suffix in paths:
   path='/extensions/'+family+'/'+suffix
   for a,b in ((1,1-2**-53),(0,2**-53),(1,1.0000000000000002)):
    try:Comparator().data(a,b,path,family)
    except AssertionError:pass
    else:raise AssertionError(('Semantic corruption escaped',path,a,b))
   rows.append({'path':path,'near_integer_corruptions_rejected':3})
 for family,suffix in (('micrography','positions/0/glyphs/0/offset/0'),('micrography','field/vectors/0/0'),('micrography','streamlines/0/points/0/1'),('decobrush','contours/0/0/0'),('decobrush','field/grid/0/x')):
  p='/extensions/'+family+'/'+suffix;c=Comparator();c.data(1,1-2**-53,p,family);assert c.differences==1
  try:c.data(1,1.000000001,p,family)
  except AssertionError:pass
  else:raise AssertionError(('Geometry drift escaped',p))
  rows.append({'path':p,'legitimate_near_integer_coordinate_accepted':True,'larger_drift_rejected':True})
 for a,b in ((float('nan'),1),(float('inf'),1),(-float('inf'),0)):
  try:Comparator().data(a,b,'/extensions/decobrush/contours/0/0/0','decobrush')
  except AssertionError:pass
  else:raise AssertionError('Nonfinite escaped')
 return {'status':'passed','semantic_paths':18,'near_integer_corruptions':54,'continuous_coordinate_controls':5,'nonfinite_controls':3,'bound_unchanged':'min(1e-10,32*binary64_epsilon*max(1,abs(a),abs(b)))','checks':rows}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path('build/adversarial/parity.json'));a=p.parse_args();result=audit();result['test_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest();a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8');print('Comparator adversarial:54 label corruptions,5 coordinate and3 nonfinite controls passed')

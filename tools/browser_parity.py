"""Independent structural/roundoff comparison for the two libm-sensitive browser families.

Never canonicalizes geometry or replaces hashes. Integer identities, keys, ordering,
text, font resources, PDF operators and non-geometric attributes remain exact.
"""
import argparse,copy,hashlib,json,math,re,sys
from pathlib import Path
import xml.etree.ElementTree as ET
from pypdf import PdfReader
from pypdf.generic import ContentStream,IndirectObject,DictionaryObject,ArrayObject,NumberObject,FloatObject,ByteStringObject,TextStringObject
NUM=re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?')
GEOMETRY_ATTRS={'d','points','transform','x','y','x1','x2','y1','y2','cx','cy','r','rx','ry','width','height','viewBox','stroke-width','stroke-miterlimit'}
ALLOWED={'micrography':('/extensions/micrography/positions/','/extensions/micrography/streamlines/','/extensions/micrography/field/','/structures/field/samples/'),
         'decobrush':('/extensions/decobrush/contours/','/extensions/decobrush/field/')}
# Leaf schemas, rather than subtree membership, distinguish continuous geometry
# from line/span/node/triangle/piece identities. Unknown fields remain exact.
CONTINUOUS={
 'micrography': tuple(re.compile(p) for p in (
  r'/extensions/micrography/positions/\d+/glyphs/\d+/(?:offset/[01]|rotation)',
  r'/extensions/micrography/streamlines/\d+/(?:points/\d+/[01]|arc/\d+|length|max_curvature)',
  r'/extensions/micrography/field/(?:points|vectors)/\d+/[01]',
  r'/extensions/micrography/field/(?:residual|min_representation_x|max_representation_x)',
  r'/extensions/micrography/field/labels/(?:attraction_scale|energy|none_aligned|all_aligned|omega)',
  r'/extensions/micrography/field/labels/samples/\d+/(?:attraction|(?:point|opposite|tangent)/[01])',
  r'/extensions/micrography/field/labels/samples/\d+/opposite/\d+/(?:distance|alignment)',
  r'/extensions/micrography/field/labels/edges/\d+/2',
  r'/structures/field/samples/\d+/(?:point|vector)/[01]')),
 'decobrush': tuple(re.compile(p) for p in (
  r'/extensions/decobrush/contours/\d+/\d+/[01]',
  r'/extensions/decobrush/field/grid/\d+/(?:x|y|source/(?:distance|u|v))',
  r'/extensions/decobrush/field/match_cost',
  r'/extensions/decobrush/field/deformation/\d+/(?:min_jacobian|min_stretch|max_stretch|residual)',
  r'/extensions/decobrush/field/matches/\d+/(?:fit|join)',
  r'/extensions/decobrush/field/matches/\d+/mesh/(?:points|rest)/\d+/[01]',
  r'/extensions/decobrush/field/matches/\d+/mesh/evidence/(?:min_jacobian|min_stretch|max_stretch|residual)'))}
class Comparator:
 def __init__(self):self.compared=0;self.differences=0;self.maximum=0.;self.max_relative_roundoff=0.
 def number(self,a,b,where,allow=True):
  assert math.isfinite(a)and math.isfinite(b),('Nonfinite',where)
  self.compared+=1
  if a==b:return
  assert allow,('Non-geometric numeric difference',where,a,b)
  delta=abs(a-b);bound=min(1e-10,32*sys.float_info.epsilon*max(1,abs(a),abs(b)))
  assert delta<=bound,('Numeric drift exceeds existing binary64 roundoff/geometry bound',where,a,b,delta,bound)
  self.differences+=1;self.maximum=max(self.maximum,delta);self.max_relative_roundoff=max(self.max_relative_roundoff,delta/bound)
 def data(self,a,b,where='',family=None):
  if isinstance(a,bool)or isinstance(b,bool):assert a is b,where
  elif isinstance(a,(int,float))and isinstance(b,(int,float)):
   permit=not(isinstance(a,int)and isinstance(b,int))and family in CONTINUOUS and any(p.fullmatch(where)for p in CONTINUOUS[family])
   self.number(a,b,where,permit)
  elif isinstance(a,dict)and isinstance(b,dict):
   assert a.keys()==b.keys(),('Object keys',where)
   for k in a:self.data(a[k],b[k],where+'/'+k,family)
  elif isinstance(a,list)and isinstance(b,list):
   assert len(a)==len(b),('Array length',where)
   for i,(x,y)in enumerate(zip(a,b)):self.data(x,y,where+'/'+str(i),family)
  else:assert type(a)==type(b)and a==b,('Exact semantic value',where,str(a)[:100],str(b)[:100])
 def numeric_text(self,a,b,where):
  assert NUM.sub('#',a)==NUM.sub('#',b),('SVG path/transform syntax',where)
  x,y=NUM.findall(a),NUM.findall(b);assert len(x)==len(y),where
  for i,(u,v)in enumerate(zip(x,y)):self.number(float(u),float(v),where+'/'+str(i))
 def svg(self,a,b):
  def walk(x,y,p):
   assert x.tag==y.tag and x.attrib.keys()==y.attrib.keys()and x.text==y.text and x.tail==y.tail,('SVG structure/text',p)
   for k in x.attrib:
    if k in GEOMETRY_ATTRS:self.numeric_text(x.attrib[k],y.attrib[k],p+'/@'+k)
    else:assert x.attrib[k]==y.attrib[k],('SVG exact attribute',p,k)
   assert len(x)==len(y),('SVG children',p)
   for i,(u,v)in enumerate(zip(x,y)):walk(u,v,p+'/'+str(i))
  walk(ET.parse(a).getroot(),ET.parse(b).getroot(),'svg')
 def pdf(self,a,b):
  aa,bb=PdfReader(a),PdfReader(b);assert len(aa.pages)==len(bb.pages)==1
  def value(x,y,p):
   if isinstance(x,IndirectObject):x=x.get_object()
   if isinstance(y,IndirectObject):y=y.get_object()
   if isinstance(x,(NumberObject,FloatObject))and isinstance(y,(NumberObject,FloatObject)):self.number(float(x),float(y),p)
   elif isinstance(x,DictionaryObject)and isinstance(y,DictionaryObject):
    keys=set(x)-{'/Length'};assert keys==set(y)-{'/Length'},('PDF resource keys',p)
    for k in keys:value(x[k],y[k],p+'/'+k)
    if hasattr(x,'get_data')or hasattr(y,'get_data'):assert x.get_data()==y.get_data(),('PDF resource stream bytes',p)
   elif isinstance(x,(list,ArrayObject))and isinstance(y,(list,ArrayObject)):
    assert len(x)==len(y),('PDF operands',p)
    for i,(u,v)in enumerate(zip(x,y)):value(u,v,p+'/'+str(i))
   elif isinstance(x,(TextStringObject,ByteStringObject))and isinstance(y,(TextStringObject,ByteStringObject)):
    raw=lambda v:v.original_bytes if isinstance(v,TextStringObject)else bytes(v)
    assert raw(x)==raw(y),('PDF text bytes',p)
   else:assert type(x)==type(y)and x==y,('PDF exact operand',p,x,y)
  for i,(pa,pb)in enumerate(zip(aa.pages,bb.pages)):
   keys=set(pa)-{'/Contents','/Parent'};assert keys==set(pb)-{'/Contents','/Parent'}
   for k in keys:value(pa[k],pb[k],'page'+str(i)+'/'+k)
   oa,ob=ContentStream(pa.get_contents(),aa).operations,ContentStream(pb.get_contents(),bb).operations
   assert len(oa)==len(ob),'PDF painting operation count'
   for j,((xa,op),(xb,oq))in enumerate(zip(oa,ob)):
    assert op==oq,('PDF operator',j,op,oq);value(xa,xb,'content/'+str(j)+'/'+op.decode('ascii'))
 def report(self):return {'numeric_values_compared':self.compared,'roundoff_differences':self.differences,'maximum_absolute_difference':self.maximum,'maximum_fraction_of_roundoff_bound':self.max_relative_roundoff,'bound':'min(1e-10,32*binary64_epsilon*max(1,abs(a),abs(b))); integer identities/text/order/topology/non-geometric fields exact'}
def controls():
 c=Comparator();detected=[]
 for name,a,b in [('drift',{'extensions':{'decobrush':{'contours':[[0.1]]}}},{'extensions':{'decobrush':{'contours':[[0.100000001]]}}}),('topology',{'structures':{'edges':[[1,2]]}},{'structures':{'edges':[[1,3]]}}),('text',{'text':'A'},{'text':'B'}),('ordering',{'ids':['a','b']},{'ids':['b','a']})]:
  try:c.data(a,b,family='decobrush')
  except AssertionError:detected.append(name)
  else:raise AssertionError('Controlled corruption escaped:'+name)
 return detected

def main():
 p=argparse.ArgumentParser();p.add_argument('--family',choices=ALLOWED,required=True);p.add_argument('--actual',type=Path,required=True);p.add_argument('--native',type=Path,required=True);p.add_argument('--expected',type=Path);a=p.parse_args();c=Comparator()
 actual,native=a.actual,a.native
 if a.expected:
  expected=json.loads(a.expected.read_text(encoding='utf8'))['families'][a.family]['artifacts']
  for name,sha in expected.items():assert hashlib.sha256((native/name).read_bytes()).hexdigest()==sha,('Native reference hash not from accepted receipt',name)
 c.data(json.loads((actual/'instance.json').read_text(encoding='utf8')),json.loads((native/'instance.json').read_text(encoding='utf8')),family=a.family)
 c.svg(actual/'pattern.svg',native/'pattern.svg');c.pdf(actual/'pattern.pdf',native/'pattern.pdf')
 print(json.dumps({'status':'passed','family':a.family,'comparison':c.report(),'controlled_corruptions_detected':controls(),'files':{side:{name:hashlib.sha256((base/name).read_bytes()).hexdigest()for name in('instance.json','pattern.svg','pattern.pdf')}for side,base in(('actual',actual),('native',native))}}))
if __name__=='__main__':main()

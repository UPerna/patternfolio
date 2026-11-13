"""Independent exact containment/attachments and80-digit curve-envelope checks."""
import argparse,pathlib,json,hashlib,math,subprocess
from PIL import Image,ImageChops,ImageStat
from pathlib import Path
from fractions import Fraction as F
from decimal import Decimal as D,localcontext
ROOT=Path(__file__).resolve().parents[1]
def exact(x):return F.from_float(float(x))
def dec(x):return D.from_float(float(x))
def orient(a,b,p):return(exact(b[0])-exact(a[0]))*(exact(p[1])-exact(a[1]))-(exact(b[1])-exact(a[1]))*(exact(p[0])-exact(a[0]))
def corners(b):return[(b[0],b[1]),(b[2],b[1]),(b[2],b[3]),(b[0],b[3])]
def bezier_axis(points):
 p,q,r,s=map(dec,points);values=[p,s];a=-p+3*q-3*r+s;b=2*(p-2*q+r);c=q-p
 if a==0:ts=[]if b==0 else[-c/b]
 else:
  discr=b*b-4*a*c;ts=[]if discr<0 else[(-b+discr.sqrt())/(2*a),(-b-discr.sqrt())/(2*a)]
 for t in ts:
  if 0<t<1:values.append((1-t)**3*p+3*(1-t)**2*t*q+3*(1-t)*t*t*r+t**3*s)
 return min(values),max(values)
def geometry(instance_path):
 count=0
 with localcontext() as ctx:
  ctx.prec=80
  x=json.loads(instance_path.read_text(encoding='utf8'));p=x['extensions']['panel'];nodes={n['id']:n for n in x['structures']['growth']['nodes']}
  assert len(p['region'])==5 and len(nodes)==1+2*p['accepted']and p['accepted']>=3
  assert len(p['attempts'])<=p['iteration_limit']and p['grid_cells']<=4096
  resources={r['id']:r for r in p['resources']}
  for place in p['placements']:
   b=place['bounds'];assert all(orient(a,p['region'][(i+1)%len(p['region'])],q)>0 for i,a in enumerate(p['region'])for q in corners(b))
   for mask in p['protected_regions']:
    m=mask['bounds'];assert b[2]<m[0]or b[0]>m[2]or b[3]<m[1]or b[1]>m[3]
   r=resources[place['resource_ref']];v=r['variants']['scene'];assert hashlib.sha256(v['content'].encode()).hexdigest()==v['sha256']
   t=place['transform'];assert t[1]==t[2]==0 and t[0]==t[3]>0
   assert all(abs((r['bounds'][i]*t[0]+t[4+i%2])-b[i])<1e-12 for i in range(4))
   for op in json.loads(v['content'])['operations']:
    if op['op']!='path':continue
    assert 'transform'not in op,'Independent oracle needs explicit matrix handling for new asset profile'
    xmin=ymin=D('Infinity');xmax=ymax=D('-Infinity');current=start=None
    for command in op['commands']:
     kind=command[0]
     if kind=='M':current=start=command[1:]
     elif kind=='C':
      xx=bezier_axis([current[0],command[1],command[3],command[5]]);yy=bezier_axis([current[1],command[2],command[4],command[6]])
      xmin=min(xmin,xx[0]);xmax=max(xmax,xx[1]);ymin=min(ymin,yy[0]);ymax=max(ymax,yy[1]);current=command[5:]
     elif kind in ['L','Z']:
      end=start if kind=='Z'else command[1:];xmin=min(xmin,dec(current[0]),dec(end[0]));xmax=max(xmax,dec(current[0]),dec(end[0]));ymin=min(ymin,dec(current[1]),dec(end[1]));ymax=max(ymax,dec(current[1]),dec(end[1]));current=end
     else:raise AssertionError(kind)
    paint=op['paint'];pad=D(0)
    if 'stroke'in paint:
     factor=max(math.sqrt(2)if paint.get('cap')=='square'else 1,paint.get('miter_limit',10)if paint.get('join','miter')=='miter'else 1);pad=dec(paint['stroke_width'])*dec(factor)/2
    rb=list(map(dec,r['bounds']));guard=D('1e-10')
    assert xmin-pad>=rb[0]-guard and ymin-pad>=rb[1]-guard and xmax+pad<=rb[2]+guard and ymax+pad<=rb[3]+guard,'Understated resource paint bounds'
    count+=1
  for n in nodes.values():
   if'parent'not in n:continue
   parent=nodes[n['parent']];expected=parent['controls'][3]if'controls'in parent else parent['point'];assert n['point']==expected
   if'controls'in n:
    assert n['controls'][0]==n['point']and n['controls'][3]==n['sampled_points'][-1]
    dep=[n['controls'][1][i]-n['controls'][0][i]for i in range(2)];direction=parent['direction'];assert abs(dep[0]*direction[1]-dep[1]*direction[0])<1e-12 and sum(dep[i]*direction[i]for i in range(2))>0
  for i,a in enumerate(p['proxies']):
   for b in p['proxies'][:i]:assert math.dist(a['center'],b['center'])>a['radius']+b['radius']
 return count

def raster(folder,name,width,height,existing):
 pdf=folder/(name+'.pdf');png=folder/(name+'-pdf.png')
 if not existing or not png.exists():
  subprocess.run(['pdftoppm','-scale-to-x',str(width),'-scale-to-y',str(height),'-png','-singlefile',str(pdf),str(folder/(name+'-pdf'))],check=True,capture_output=True)
 return Image.open(png).convert('RGB')
def rendered(folder,existing):
 reports=[]
 for name,w,h in [('panel',720,660),('authored',1260,1782),('grown',1260,1782)]:
  pdf=raster(folder,name,w,h,existing);svg_path=folder/(name+'-svg.png')
  if not existing:
   subprocess.run(['inkscape',str(folder/(name+'.svg')),'--export-area-page','--export-width='+str(w),'--export-height='+str(h),'--export-filename='+str(svg_path)],check=True,capture_output=True)
  svg=Image.open(svg_path).convert('RGB')
  assert pdf.size==svg.size==(w,h),'raster geometry mismatch'
  delta=ImageChops.difference(pdf,svg);mae=sum(ImageStat.Stat(delta).mean)/765
  assert mae<0.04,(name,mae)
  for image in [pdf,svg]:assert ImageChops.difference(image,Image.new('RGB',image.size,'white')).getbbox(),'empty vector output'
  if name=='panel':
   bare=raster(folder,'panel-unmasked',w,h,existing)
   assert ImageChops.difference(pdf,bare).getbbox()is None,'panel relied on the final reservation clip'
   for image in [pdf,svg]:
    roi=image.crop((362,350,418,418))
    assert all(lo==255 for lo,hi in roi.getextrema()),'protected panel ink'
  reports.append({'fixture':name,'pixels':[w,h],'mean_absolute_error':mae})
 return reports

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--directory',type=Path)
 parser.add_argument('--existing-rasters',action='store_true')
 args=parser.parse_args()
 folders=[args.directory] if args.directory else sorted((ROOT/'build/botanical').glob('*'))
 checked=0
 for folder in folders:
  receipts=sorted(folder.glob('receipt-*.json'))
  if not receipts:continue
  reports=[json.loads(p.read_text(encoding='utf8'))for p in receipts]
  reference=reports[0]
  source=[{'path':r['path'],'sha256':hashlib.sha256((ROOT/r['path']).read_bytes().replace(b'\r\n',b'\n')).hexdigest()}for r in reference['source']]
  if source!=reference['source']:
   if args.directory:raise AssertionError('requested botanical folder has stale source evidence')
   continue
  assert hashlib.sha256(json.dumps(source,ensure_ascii=False,separators=(',',':'),sort_keys=True).encode()).hexdigest()==reference['source_digest']
  for receipt in reports:
   assert receipt['outputs']==reference['outputs'],'different output bytes between runtime receipts'
   assert receipt['panel']['status']=='complete'
   for name,sha in receipt['outputs'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==sha,name
   actual=receipt['panel']['outputs']
   for row,name in zip(actual,['panel.instance','panel.scene']):assert row['sha256']==receipt['outputs'][name]
  paths=geometry(folder/'panel.instance')
  result={'stage':'08','source_digest':reference['source_digest'],'rasterizers':'local Poppler/librsvg'if args.existing_rasters else'Inkscape/Poppler','checked_paths':paths,'exact_placement_and_attachment_checks':'passed','unmasked_pdf_matches':'pixel exact','fixtures':rendered(folder,args.existing_rasters)}
  (folder/('oracle-local.json'if args.existing_rasters else'oracle.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
  print('botanical_oracle: exact attachment/containment,',paths,'independent paint envelopes and actual masked/unmasked PDF/SVG images passed',reference['source_digest'])
  checked+=1
 assert checked,'No current-source botanical verification reports'
if __name__=='__main__':main()

"""Independent PDF/XML inspection of real editor task exports, not download events."""
import argparse,hashlib,json,math,pathlib,re,xml.etree.ElementTree as ET
from pypdf import PdfReader
from pypdf.generic import ContentStream

def verify(folder):
 receipt=json.loads((folder/'receipt.json').read_text(encoding='utf8'));results={}
 for name,case in receipt['cases'].items():
  root=folder/name;recipe=json.loads((root/'recipe.json').read_text(encoding='utf8'))
  crop=recipe['view']['crop'];width,height=crop[2]-crop[0],crop[3]-crop[1]
  svg=ET.parse(root/'pattern.svg').getroot();box=[float(x)for x in svg.attrib['viewBox'].split()]
  assert math.isclose(box[2],width,abs_tol=1e-11)and math.isclose(box[3],height,abs_tol=1e-11),name
  assert math.isclose(float(svg.attrib['width'][:-2]),width,abs_tol=1e-11),name
  assert math.isclose(float(svg.attrib['height'][:-2]),height,abs_tol=1e-11),name
  assert not any(e.tag.rsplit('}',1)[-1]in('image','foreignObject')for e in svg.iter()),name
  pdf=PdfReader(root/'pattern.pdf');assert len(pdf.pages)==1,name;page=pdf.pages[0]
  assert math.isclose(float(page.mediabox.width),width*72/2.54,abs_tol=1e-7),name
  assert math.isclose(float(page.mediabox.height),height*72/2.54,abs_tol=1e-7),name
  operations=ContentStream(page['/Contents'],pdf).operations;operators=[op.decode('ascii')for args,op in operations]
  assert any(op in operators for op in('m','BT')),name
  assert page.get('/Resources',{}).get('/XObject',{})=={},name
  if name=='border-monochrome':
   assert not any(op in operators for op in('rg','RG','k','K','cs','CS')),name
   assert 'g'in operators or 'G'in operators,name
  searchable=None
  if name=='microgram':
   searchable=''.join(page.extract_text().split());expected=''.join(recipe['design']['inputs']['text'].split())
   assert searchable==expected,('Native Micrography PDF text mismatch',searchable,expected)
   for font in page['/Resources']['/Font'].values():assert '/ToUnicode'in font.get_object(),name
  results[name]={'physical_cm':[width,height],'pdf_page_points':[float(page.mediabox.width),float(page.mediabox.height)],
    'pdf_operations':len(operators),'svg_elements':sum(1 for _ in svg.iter()),'vector_only':True,
    'searchable_text_characters':len(searchable)if searchable is not None else None,
    'sha256':{file:hashlib.sha256((root/file).read_bytes()).hexdigest()for file in('recipe.json','pattern.svg','pattern.pdf')}}
 return {'status':'passed','source_digest':receipt['source_digest'],'cases':results,'scope':'Independent XML/PDF syntax, physical units, vector-only resources, DeviceGray and searchable text; visual review remains separate'}

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('folder',type=pathlib.Path);args=parser.parse_args()
 result=verify(args.folder);(args.folder/'vector-inspection.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
 print('Independently inspected real editor vectors:',len(result['cases']))

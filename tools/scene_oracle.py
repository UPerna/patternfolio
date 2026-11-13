"""Independent Poppler/Inkscape structural, physical, raster and reservation QA.

Requires existing scenecheck outputs, Pillow and Poppler/Inkscape. The local
--existing-rasters option records separately prepared librsvg/Poppler images;
it does not stand in for the required Linux Inkscape run.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image, ImageChops, ImageStat, ImageFilter

ROOT=Path(__file__).resolve().parents[1]
NS={'s':'http://www.w3.org/2000/svg'}
def run(args):return subprocess.run(args,check=True,capture_output=True).stdout
def pixel(image,b,x,y):
    return image.getpixel((min(image.width-1,int((x-b[0])/(b[2]-b[0])*image.width)),min(image.height-1,int((b[3]-y)/(b[3]-b[1])*image.height))))
def inspect(folder,existing=False):
    receipts=sorted(folder.glob('receipt-*.json'));assert receipts,'Run scenecheck first'
    receipt=json.loads(receipts[0].read_text())
    for other in receipts[1:]:
        obj=json.loads(other.read_text());assert obj['source_digest']==receipt['source_digest'] and obj['fixtures']==receipt['fixtures'],'Lua runtime outputs differ'
    for source in receipt['source']:
        assert hashlib.sha256((ROOT/source['path']).read_bytes().replace(b'\r\n',b'\n')).hexdigest()==source['sha256'],'Stale source evidence'
    report={'stage':'06','source_digest':receipt['source_digest'],'rasterizers':'precomputed local librsvg/Poppler' if existing else 'Inkscape/Poppler','fixtures':[]}
    for item in receipt['fixtures']:
        name=item['name'];b=item['bounds'];width,height=b[2]-b[0],b[3]-b[1];dims=(round(width*60),round(height*60))
        for output in item['outputs'].values():assert hashlib.sha256((ROOT/output['path']).read_bytes()).hexdigest()==output['sha256'],'Output digest mismatch'
        svg=ET.parse(folder/(name+'.svg')).getroot()
        assert math.isclose(float(svg.attrib['width'][:-2]),width) and svg.attrib['width'].endswith('cm')
        assert math.isclose(float(svg.attrib['height'][:-2]),height) and svg.attrib['height'].endswith('cm')
        assert [float(v) for v in svg.attrib['viewBox'].split()]==[0,0,width,height]
        assert svg.findall('.//s:path',NS) and not svg.findall('.//s:image',NS)
        assert all(p.get('data-semantic-ref') for p in svg.findall('.//s:g/s:path',NS))
        info=run(['pdfinfo',str(folder/(name+'.pdf'))]).decode('utf8')
        assert 'Pages:           1' in info
        match=re.search(r'Page size:\s+([\d.]+) x ([\d.]+) pts',info);assert match
        assert abs(float(match[1])-width*72/2.54)<0.02 and abs(float(match[2])-height*72/2.54)<0.02,'PDF physical bounds changed'
        pdf=(folder/(name+'.pdf')).read_bytes();assert b'/Subtype /Image' not in pdf
        if not existing:
            run(['pdftoppm','-scale-to-x',str(dims[0]),'-scale-to-y',str(dims[1]),'-png','-singlefile',str(folder/(name+'.pdf')),str(folder/(name+'-pdf'))])
            run(['inkscape',str(folder/(name+'.svg')),'--export-background=white','--export-background-opacity=1',f'--export-width={dims[0]}',f'--export-height={dims[1]}',f'--export-filename={folder/(name+"-svg.png")}'])
        images=[Image.open(folder/(name+'-'+kind+'.png')).convert('RGB') for kind in ('pdf','svg')]
        assert images[0].size==images[1].size==dims,'Raster dimensions differ'
        mean=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/3/255
        blurred=sum(ImageStat.Stat(ImageChops.difference(*(im.filter(ImageFilter.GaussianBlur(1)) for im in images))).mean)/3/255
        assert mean<0.04 and blurred<0.025,(name,'independent raster mismatch',mean,blurred)
        protected=[]
        for region in item['protected_regions']:
            a=region['bounds'];box=(math.ceil((a[0]-b[0])*60)+2,math.ceil((b[3]-a[3])*60)+2,math.floor((a[2]-b[0])*60)-2,math.floor((b[3]-a[1])*60)-2)
            assert box[0]<box[2] and box[1]<box[3],'Reservation ROI too small to test'
            extrema=[im.crop(box).getextrema() for im in images]
            assert all(low>=254 for ex in extrema for low,high in ex),'Actual protected-region ink; average image error cannot waive this'
            protected.append({'bounds':a,'pixel_box':box,'minimum_channel':[min(low for low,high in ex) for ex in extrema]})
        if name=='clipstress':
            # Source-over multiply, derived independently from the numeric colors:
            # B=.3*(.8,.9,.95)+.7*(.2,.5,.8); C=B*(.4+.6*(.9,.2,.1)).
            # Inkscape's clipped-ancestor blend issue is invisible to an average
            # error threshold, so require the actual interior color in each image.
            for im in images:
                p=pixel(im,b,0.9,1.0);expected=(91,82,99)
                assert all(abs(a-e)<=3 for a,e in zip(p,expected)),('multiply with clipped backdrop',p,expected)
            # Analytic dash intervals away from transitions; catches a sign error
            # that a whole-image average can conceal.
            for im in images:
                for x in (0.05,0.10,0.45,0.55,0.95,1.05):
                    p=pixel(im,b,x,0.3);assert p[0]>p[2]+60,('dash ink',x,p)
                for x in (0.25,0.30,0.75,0.80):
                    p=pixel(im,b,x,0.3);assert p[2]>p[0]+50,('dash gap',x,p)
                p=pixel(im,b,5.1,1.2);assert p[2]>p[1]>p[0],'Evenodd hole filled'
                p=pixel(im,b,4.65,1.2);assert p[1]>p[2] and p[1]>p[0],'Evenodd outer ring missing'
        if name=='mono':
            assert b' rg' not in pdf and b' RG' not in pdf and b' g\n' in pdf,'Monochrome PDF emitted RGB operators'
            assert all(all(r==g==bl for r,g,bl in im.getdata()) for im in images),'Monochrome raster has color'
        if name=='text':
            nodes=svg.findall('.//s:text',NS);assert [t.attrib['aria-label'] for t in nodes]==['αA','Aα'],'SVG logical reading order lost'
            assert '@font-face' in (folder/(name+'.svg')).read_text() and b'/Subtype /Type3' in pdf and b'/ToUnicode' in pdf
            assert b'/ca 0 /CA 0' in pdf,'Type3 semantic layer needs explicit zero opacity, not Tr alone'
            probe=folder/'text-mode0.pdf';probe_bytes=pdf.replace(b'Tf 3 Tr',b'Tf 0 Tr')
            assert probe_bytes!=pdf
            if probe.exists():assert probe.read_bytes()==probe_bytes
            else:probe.write_bytes(probe_bytes)
            run(['pdftoppm','-scale-to-x',str(dims[0]),'-scale-to-y',str(dims[1]),'-png','-singlefile',str(probe),str(folder/'text-mode0')])
            assert ImageChops.difference(images[0],Image.open(folder/'text-mode0.png').convert('RGB')).getbbox() is None,'Type3 logical layer paints visible glyphs'
            if existing:
                from pypdf import PdfReader
                content=PdfReader(folder/(name+'.pdf')).pages[0].extract_text()
            else:content=run(['pdftotext','-raw',str(folder/(name+'.pdf')),'-']).decode('utf8')
            assert ''.join(content.split())=='αAAα',('Unicode extraction/order lost',ascii(content))
        report['fixtures'].append({'name':name,'dimensions':dims,'mean_absolute_error':mean,'blurred_mean_absolute_error':blurred,'protected_regions':protected,'pdf_sha256':item['outputs']['pdf']['sha256'],'svg_sha256':item['outputs']['svg']['sha256']})
    target=folder/('oracle-local.json' if existing else 'oracle.json')
    encoded=json.dumps(report,indent=2,ensure_ascii=False)+'\n'
    if target.exists():assert target.read_text(encoding='utf8')==encoded,'Existing oracle differs; preserve and investigate'
    else:target.write_text(encoded,encoding='utf8')
    print('scene_oracle: six vector pairs, physical bounds, Unicode/order, dash/winding probes and strict protected ink passed',receipt['source_digest'])
    return report
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',type=Path);parser.add_argument('--existing-rasters',action='store_true');args=parser.parse_args()
    folders=[args.directory] if args.directory else sorted((ROOT/'build/scenes').glob('*'))
    assert folders,'No scene evidence found'
    for folder in folders:inspect(folder,args.existing_rasters)

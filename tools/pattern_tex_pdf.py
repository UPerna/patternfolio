"""Independent PDF placement and protected-ink measurements for the TeX adapter."""
import hashlib
from pathlib import Path
import subprocess
from pypdf import PdfReader
from pypdf.generic import ContentStream
from PIL import Image

IDENTITY=(1,0,0,1,0,0)


def compose(a,b):
    return (a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],
            a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],
            a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5])


def transform(m,p):
    return m[0]*p[0]+m[2]*p[1]+m[4],m[1]*p[0]+m[3]*p[1]+m[5]


def forms(reader,page):
    found=[]

    def walk(stream,resources,parent,depth):
        assert depth<16,"Unexpected nested Form depth"
        resources=resources.get_object()
        matrix=parent;stack=[]
        for operands,operator in ContentStream(stream,reader).operations:
            if operator==b'q':
                stack.append(matrix)
            elif operator==b'Q':
                assert stack,"Unbalanced PDF graphics stack"
                matrix=stack.pop()
            elif operator==b'cm':
                matrix=compose(matrix,tuple(float(x) for x in operands))
            elif operator==b'Do':
                item=resources['/XObject'][operands[0]].get_object()
                if item.get('/Subtype')!='/Form':
                    continue
                child=compose(matrix,tuple(float(x) for x in item.get('/Matrix',IDENTITY)))
                box=[float(x) for x in item['/BBox']]
                corners=[transform(child,(x,y)) for x in (box[0],box[2]) for y in (box[1],box[3])]
                found.append({'file':str(item.get('/PTEX.FileName','')),
                    'content_sha256':hashlib.sha256(item.get_data().strip()).hexdigest(),
                    'bounds_cm':[min(p[0] for p in corners)*2.54/72,min(p[1] for p in corners)*2.54/72,
                                 max(p[0] for p in corners)*2.54/72,max(p[1] for p in corners)*2.54/72],
                    'matrix':child})
                walk(item,item.get('/Resources',resources),child,depth+1)
        assert not stack,"Unbalanced PDF graphics stack"

    walk(page.get_contents(),page['/Resources'],IDENTITY,0)
    return found


def locate(found,source):
    source=Path(source)
    reader=PdfReader(source)
    signature=hashlib.sha256(reader.pages[0].get_contents().get_data().strip()).hexdigest()
    result=[row for row in found if Path(row['file']).name==source.name or row['content_sha256']==signature]
    assert len(result)==1,(source.name,'Expected one imported shared PDF',result)
    return result[0]


def placement(found,source,expected,tolerance=.01):
    row=locate(found,source)
    error=max(abs(a-b) for a,b in zip(row['bounds_cm'],expected))
    assert error<=tolerance,(source.name,row['bounds_cm'],expected,error)
    m=row['matrix']
    assert m[0]>0 and m[3]>0 and abs(m[1])<1e-8 and abs(m[2])<1e-8,'Imported ornament text was rotated/reflected'
    return {'pdf':Path(source).name,'measured_cm':row['bounds_cm'],'expected_cm':expected,
            'maximum_absolute_error_cm':error,'tolerance_cm':tolerance}


def raster(pdf,destination,dpi=144):
    subprocess.run(['pdftoppm','-r',str(dpi),'-png','-singlefile',str(pdf),str(destination)],check=True,capture_output=True)
    return Image.open(str(destination)+'.png').convert('RGB')


def colored(image,region,crop,dpi=144):
    # Physical page cm -> this child PDF's local raster, ignoring a two-pixel edge.
    scale=dpi/2.54
    bounds=(max(0,round((region[0]-crop[0])*scale)+2),max(0,round((crop[3]-region[3])*scale)+2),
            min(image.width,round((region[2]-crop[0])*scale)-2),min(image.height,round((crop[3]-region[1])*scale)-2))
    assert bounds[0]<bounds[2] and bounds[1]<bounds[3],(region,crop,'No measurable reservation interior')
    crop_image=image.crop(bounds)
    pixels=crop_image.get_flattened_data() if hasattr(crop_image,'get_flattened_data') else crop_image.getdata()
    return sum(max(p)-min(p)>15 for p in pixels)

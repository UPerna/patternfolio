"""Prepare the small GFL/LPPL real-glyph fixture; never rewrites it implicitly.

Requires fontTools==4.60.1. Supply the pinned Latin Modern Math1.959 OTF via
--font and an explicit --output (normally build/scene-font.json).
"""
import argparse
import base64
import hashlib
from io import BytesIO
import json
from pathlib import Path

import fontTools
from fontTools import subset
from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

SOURCE_SHA256 = '6075562b771f8b82f0c179e363389684f2dd09de30038269e2628e504bd7be0f'
SOURCE_COMMIT = 'a0bb94c14db8e1f950d344e1eb1d5947c0182665'
FAMILY = 'Pattern Scene Fixture'

class Commands(BasePen):
    def __init__(self, glyphs):
        super().__init__(glyphs)
        self.commands=[]
    def _moveTo(self,p): self.commands.append(['M',*p])
    def _lineTo(self,p): self.commands.append(['L',*p])
    def _curveToOne(self,a,b,c): self.commands.append(['C',*a,*b,*c])
    def _qCurveToOne(self,control,end):
        start=self._getCurrentPoint()
        a=tuple(start[i]+2/3*(control[i]-start[i]) for i in (0,1))
        b=tuple(end[i]+2/3*(control[i]-end[i]) for i in (0,1))
        self.commands.append(['C',*a,*b,*end])
    def _closePath(self): self.commands.append(['Z'])
    def _endPath(self): raise ValueError('Open font contour is unsupported in this fixture')

def outline(font, cp):
    name=font.getBestCmap()[cp];glyphs=font.getGlyphSet()
    pen=Commands(glyphs);glyphs[name].draw(pen)
    bound=BoundsPen(glyphs);glyphs[name].draw(bound)
    return {'id':f'glyph/{cp}','unicode':chr(cp),'advance':font['hmtx'].metrics[name][0],
            'bounds':list(bound.bounds or (0,0,0,0)),'commands':pen.commands}

def prepare(path):
    if fontTools.version!='4.60.1':raise ValueError('Use pinned fontTools4.60.1; investigate changes before upgrading')
    data=path.read_bytes()
    if hashlib.sha256(data).hexdigest()!=SOURCE_SHA256:raise ValueError('Source font differs from pinned Latin Modern Math1.959')
    font=TTFont(BytesIO(data),recalcTimestamp=False)
    cps=(65,945);glyphs=[outline(font,cp) for cp in cps]
    original_names={str(cp):font.getBestCmap()[cp] for cp in cps}
    copyrights=sorted({n.toUnicode() for n in font['name'].names if n.nameID==0})
    options=subset.Options();options.hinting=False;options.recalc_timestamp=False
    options.drop_tables.extend(['MATH','GSUB','GPOS','GDEF','DSIG'])
    options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*']
    subsetter=subset.Subsetter(options=options);subsetter.populate(unicodes=cps);subsetter.subset(font)
    replacements={1:FAMILY,2:'Regular',3:'PatternSceneFixture-1.000',4:FAMILY+' Regular',5:'Version1.000; derived fixture from Latin Modern Math1.959',6:'PatternSceneFixture-Regular',16:FAMILY,17:'Regular'}
    for record in font['name'].names:
        if record.nameID in replacements:
            record.string=replacements[record.nameID].encode(record.getEncoding())
    if 'CFF ' in font:
        cff=font['CFF '].cff;cff.fontNames[0]='PatternSceneFixture-Regular'
        cff.topDictIndex[0].FamilyName=FAMILY;cff.topDictIndex[0].FullName=FAMILY+' Regular'
    font['head'].created=font['head'].modified=2082844800
    buffer=BytesIO();font.save(buffer,reorderTables=True);embedded=buffer.getvalue()
    reopened=TTFont(BytesIO(embedded),recalcTimestamp=False)
    assert [outline(reopened,cp) for cp in cps]==glyphs,'Subsetting changed glyph geometry or metrics'
    sha=hashlib.sha256(embedded).hexdigest()
    return {'id':'font/scene-fixture','kind':'font','profile':'positioned-outlines-v1',
      'units_per_em':font['head'].unitsPerEm,'family':FAMILY,
      'license':'GUST Font License / LPPL1.3c-or-later; see docs/fonts/GUST-FONT-LICENSE.md and LPPL-1.3c.md',
      'font_sha256':sha,'glyphs':glyphs,
      'variants':{'opentype':{'encoding':'base64','content':base64.b64encode(embedded).decode('ascii'),'sha256':sha,'media_type':'font/otf'}},
      'provenance':{'source':'Latin Modern Math','source_version':'1.959','source_sha256':SOURCE_SHA256,
        'source_blob_sha1':'0e4642e916c3e8206c8bf9c490c90eb3b20d9365',
        'source_pinned_copy':f'https://github.com/valxyz/fonts-lm-math/blob/{SOURCE_COMMIT}/fonts/latinmodern-math.otf',
        'complete_original_work':'https://mirrors.ctan.org/fonts/lm-math.zip',
        'source_copyright':copyrights,'source_glyph_names':original_names,'preparer':'fontTools4.60.1 / preparescenefont-v1',
        'modified_notice':'Derived two-glyph fixture: renamed family and files, removed other glyphs, hints and shaping/math tables, fixed timestamps; glyph outlines and advances retained. Original authors do not provide support for this fixture.',
        'changes_file':'docs/fonts/README-PatternSceneFixture.md'}}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--font',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();result=prepare(args.font)
    if args.output.exists():
        if json.loads(args.output.read_text(encoding='utf8'))!=result:raise SystemExit('Existing fixture differs; explicit review required, not overwriting')
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
    print('preparescenefont: genuine A/alpha outlines and renamed embedded subset verified',result['font_sha256'])

if __name__=='__main__':main()

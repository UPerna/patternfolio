"""Independent audit of cyclic-sector traversal and crossing incidence."""
from collections import Counter, defaultdict
from pathlib import Path
from math import atan2, dist
import argparse, hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {'closed': (2,4,0), 'border': (2,8,2), 'irregular': (1,10,0), 'botanical': (1,3,2)}
def load(p):
    return json.loads(p.read_text(encoding='utf8'))
def sha(data):
    return hashlib.sha256(data).hexdigest()
def half(text):
    return tuple(text.split('/'))
def audit(instance, name):
    s=instance['extensions']['celtic']['scaffold']
    verts={v['id']:v['point'] for v in s['vertices']}
    edges={e['id']:(e['from'],e['to']) for e in s['edges']}
    around=defaultdict(list)
    for e,(a,b) in edges.items():
        for u,v in ((a,b),(b,a)):
            x,y=verts[u]; q,r=verts[v]
            around[u].append((atan2(r-y,q-x), e))
    for v in around:
        around[v]=[e for _,e in sorted(around[v])]
    cuts={(p['vertex'],p['edge']) for p in s.get('open_sectors',[])}
    def next_half(h):
        e,v,d=h
        ring=around[v]; i=ring.index(e)
        if d=='R':
            return None if (v,e) in cuts else (ring[(i+1)%len(ring)],v,'L')
        prev=ring[(i-1)%len(ring)]
        return None if (v,prev) in cuts else (prev,v,'R')
    strands=instance['structures']['strands']
    cs,cr,ps=(strands[k] for k in ('components','crossings','ports'))
    assert (len(cs),len(cr),len(ps))==EXPECTED[name]
    ports={half(p['half']):p for p in ps}
    assert len(ports)==len(ps)
    expected_ports={h for e,vs in edges.items() for v in vs for d in ('L','R') if next_half(h:=(e,v,d)) is None}
    assert ports.keys()==expected_ports
    crossings={c['id']:c for c in cr}
    covered=Counter()
    for c in cs:
        visits=c['encounters']
        assert visits
        entry,exit=half(visits[0]['enter']),half(visits[-1]['leave'])
        if c['closed']:
            assert c['endpoints']==[] and next_half(exit)==entry
        else:
            assert c['endpoints']==[ports[entry]['id'],ports[exit]['id']]
            assert ports[entry]['component']==ports[exit]['component']==c['id']
        for i,use in enumerate(visits):
            e,v,d=half(use['enter']); f,w,g=half(use['leave'])
            assert e==f and d==g and {v,w}==set(edges[e])
            assert use['branch']==f'{e}/{d}' and use['crossing']==f'crossing/{e}'
            covered[e,d]+=1
            crossing=crossings[use['crossing']]
            mid=[sum(verts[z][k] for z in edges[e])/2 for k in range(2)]
            assert dist(mid,crossing['point'])<1e-13
            role=use['role'];assert crossing[role]==c['id'] and crossing[role+'_branch']==use['branch']
            follow=visits[i+1] if i+1<len(visits) else visits[0] if c['closed'] else None
            if follow:
                assert next_half((f,w,g))==half(follow['enter'])
                assert role!=follow['role']
    assert covered==Counter({(e,d):1 for e in edges for d in ('L','R')})
    a=instance['extensions']['celtic'].get('attachment')
    if name=='botanical':
        p=next(p for p in ps if p['id']==a['port'])
        assert p['point']==a['root']==a['points'][0]
        assert a['port']==s['botanical_port']
    else:
        assert a is None
    return len(covered)
def raster(folder, existing):
    from PIL import Image, ImageChops, ImageStat
    names=(*EXPECTED,'closed-narrow','closed-cropped')
    result={}
    for name in names:
        edge=102 if name=='closed-cropped' else 360
        a,b=[folder/f'{name}-{kind}.png' for kind in ('pdf','svg')]
        if not existing:
            subprocess.run(['pdftoppm','-r','152.4','-W',str(edge),'-H',str(edge),'-png','-singlefile',str(folder/f'{name}.pdf'),
                            str(a.with_suffix(''))],check=True)
            subprocess.run(['inkscape',str(folder/f'{name}.svg'),'--export-background=white',
                            '--export-background-opacity=1',f'--export-width={edge}',
                            f'--export-filename={b}'],check=True)
        images=[Image.open(p).convert('RGB') for p in (a,b)]
        assert images[0].size==images[1].size==(edge,edge),(name,[i.size for i in images])
        white=Image.new('RGB',(edge,edge),'white')
        ink=[sum(i.convert('L').histogram()[:205]) for i in images]
        assert min(ink)>20,name
        boxes=[ImageChops.difference(i,white).getbbox() for i in images]
        assert max(abs(x-y) for x,y in zip(*boxes))<=2,(name,boxes)
        error=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
        assert error<.013,(name,error)
        result[name]={'ink_pixels':ink,'ink_bounds':boxes,'mean_normalized_error':error}
    if not existing:
        subprocess.run(['pdftoppm','-r','508','-png','-singlefile',str(folder/'irregular.pdf'),
                        str(folder/'irregular-detail-pdf')],check=True)
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--existing-rasters",action="store_true")
    existing=parser.parse_args().existing_rasters
    verified=0
    for folder in sorted((ROOT/'build/celtic').glob('*')):
        files=sorted(folder.glob('receipt-Lua-*.json'))
        if not files:continue
        r=load(files[0])
        if not all(sha((ROOT/f['path']).read_bytes().replace(b'\r\n',b'\n'))==f['sha256'] for f in r['source']):continue
        assert folder.name==r['source_digest']
        for p in files[1:]:
            assert load(p)['outputs']==r['outputs']
        for path,digest in r['outputs'].items():
            assert sha((folder/path).read_bytes())==digest,path
        cases={name:audit(load(folder/(name+'.instance')),name) for name in EXPECTED}
        (folder/'oracle.json').write_text(json.dumps({'stage':'10','source_digest':folder.name,'verified_branches':cases,
          'outputs':len(r['outputs']),'raster':raster(folder,existing)},indent=2)+'\n',encoding='utf8')
        verified+=1
        print('celtic_oracle:',cases,'branches verified; output hashes:',len(r['outputs']))
    assert verified,'no current-source Celtic receipts'
if __name__=='__main__':
    main()

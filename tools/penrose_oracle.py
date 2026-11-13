"""Independent high-precision dual and finite coverage audit for Penrose P3."""
from collections import Counter, defaultdict
from decimal import Decimal as D, ROUND_CEILING, getcontext
from itertools import combinations
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

getcontext().prec=76
ROOT=Path(__file__).resolve().parents[1]
EPS=D('1e-62')
NAMES=('small','medium','large','offset','indigo')
rt=D(5).sqrt()
c1,c2=(rt-1)/4,-(rt+1)/4
s1,s2=(10+2*rt).sqrt()/4,(10-2*rt).sqrt()/4
U=((D(1),D(0)),(c1,s1),(c2,s2),(c2,-s2),(c1,-s1))
def load(p):return json.loads(p.read_text(encoding='utf8'))
def sha(b):return hashlib.sha256(b).hexdigest()
def decimal(x):return D(str(x))
def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def dot(a,b):return a[0]*b[0]+a[1]*b[1]
def v(a,b):return (b[0]-a[0],b[1]-a[1])
def mid(a,b):return tuple((x+y)/2 for x,y in zip(a,b))
def cyclic(a):return zip(a,a[1:]+a[:1])
def project(lift):
    return tuple(sum(k*u[j] for k,u in zip(lift,U)) for j in range(2))
def box(poly):
    x,y=zip(*poly)
    return min(x),min(y),max(x),max(y)
def meet(a,b,eps=EPS):
    return a[0]<=b[2]+eps and b[0]<=a[2]+eps and a[1]<=b[3]+eps and b[1]<=a[3]+eps
def quad(b):return [(b[0],b[1]),(b[2],b[1]),(b[2],b[3]),(b[0],b[3])]
def polygon_area(poly):
    return abs(sum(cross(a,b) for a,b in cyclic(poly)))/2 if poly else D(0)
def clip(poly,region):
    for a,b in cyclic(region):
        out=[]
        edge=v(a,b)
        if not poly:return []
        for p,q in cyclic(poly):
            u,w=cross(edge,v(a,p)),cross(edge,v(a,q))
            u0,w0=u>=-EPS,w>=-EPS
            if u0:out.append(p)
            if u0!=w0:
                t=u/(u-w)
                out.append(tuple(x+t*(y-x) for x,y in zip(p,q)))
        poly=out
    return poly

def grid_tile(i,j,m,n,phase):
    a,b=U[i],U[j]
    r,s=D(m)-phase[i],D(n)-phase[j]
    divisor=cross(a,b)
    z=((r*b[1]-a[1]*s)/divisor,(a[0]*s-r*b[0])/divisor)
    k=[]
    for l,u in enumerate(U):
        if l==i:k.append(m)
        elif l==j:k.append(n)
        else:
            value=dot(z,u)+phase[l]
            assert abs(value-value.to_integral_value())>EPS
            k.append(int(value.to_integral_value(rounding=ROUND_CEILING)))
    first,second=(i,j) if divisor>0 else (j,i)
    def bumped(indices):
        return tuple(n+(l in indices) for l,n in enumerate(k))
    corners=[tuple(k),bumped({first}),bumped({i,j}),bumped({second})]
    poly=[project(a) for a in corners]
    return corners,poly

def full_candidates(cert):
    phase=[D(n)/cert['phase']['denominator'] for n in cert['phase']['numerators']]
    assert sum(cert['phase']['numerators'])==0
    assert len(cert['phase']['regularity'])==10 and all(any(w['residue']) for w in cert['phase']['regularity'])
    numerators=cert['phase']['numerators'];denominator=cert['phase']['denominator']
    phi=(1+rt)/2
    def coefficients(x):
        fits=[(a,b) for a in range(-2,3) for b in range(-2,3) if abs(x-a-b*phi)<EPS]
        assert len(fits)==1,x
        return fits[0]
    residues={}
    for i,j,l in combinations(range(5),3):
        den=cross(U[i],U[j])
        a=coefficients(cross(U[l],U[j])/den)
        b=coefficients(cross(U[i],U[l])/den)
        r=((-a[0]*numerators[i]-b[0]*numerators[j]+numerators[l])%denominator,
           (-a[1]*numerators[i]-b[1]*numerators[j])%denominator)
        assert r!=(0,0)
        residues[(i+1,j+1,l+1)]=r
    assert residues=={tuple(w['families']):tuple(w['residue']) for w in cert['phase']['regularity']}
    normal=[decimal(v) for v in cert['normalized_selection_box']]
    wide=[x+d for x,d in zip(normal,(D('-2.125'),D('-2.125'),D('2.125'),D('2.125')))]
    epsilon=max(D(1),*map(abs,map(decimal,cert['normalized_query'])))*D('1e-12')
    ranges=cert['line_ranges']; n=0
    kept={};neighbors={};examined=0
    for i,j in combinations(range(5),2):
        a,b=ranges[i],ranges[j]
        examined+=(a[1]-a[0]+1)*(b[1]-b[0]+1)
        # Two additional indices each way check conservatism at the actual boundary.
        for m in range(a[0]-2,a[1]+3):
            for n0 in range(b[0]-2,b[1]+3):
                corners,poly=grid_tile(i,j,m,n0,phase)
                bounds=box(poly)
                if meet(bounds,wide,epsilon):
                    assert a[0]<=m<=a[1] and b[0]<=n0<=b[1]
                    address=(i+1,j+1,m,n0)
                    neighbors[address]=(corners,poly)
                    if meet(bounds,normal,epsilon):kept[address]=(corners,poly)
    assert examined==cert['candidate_crossings']
    assert len(neighbors)==cert['neighbor_patch_rhombi']
    return kept,neighbors

def expected_arrow(a,b,poly,i):
    u,w=sum(a),sum(b)
    assert abs(u-w)==1
    if min(u,w)==1 or max(u,w)==4:
        return ('green',2,a,b) if (u,w) in ((2,1),(3,4)) else ('green',2,b,a)
    a0=poly[i]
    acute=dot(v(a0,poly[i-1]),v(a0,poly[(i+1)%4]))>0
    return ('red',1,a,b) if acute else ('red',1,b,a)

def audit(instance):
    ext=instance['extensions']['penrose']; cert=ext['certificate']; request=ext['request']
    assert ext['route']=='projection_multigrid' and ext['capabilities']['projection_multigrid']['implemented']
    origin=tuple(map(decimal,request['frame']['origin']));step=decimal(request['step_cm'])
    assert all(abs((decimal(value)-origin[i%2])/step-decimal(cert['normalized_query'][i]))<D('1e-13')
               for i,value in enumerate(request['world_query']))
    kept,neighbors=full_candidates(cert)
    topology=instance['structures']['tiling']
    vertex={v['id']:v for v in topology['vertices']}
    edge={e['id']:e for e in topology['edges']}
    lookup={tuple(c['address']):c for c in topology['cells']}
    assert lookup.keys()==kept.keys()
    for id_,p in vertex.items():
        k=tuple(p['lift']);assert p['index']==sum(k) in (1,2,3,4)
        assert id_.endswith('/v/'+'/'.join(map(str,k)))
        point=project(k)
        assert all(abs(decimal(p['point'][j])-(origin[j]+step*point[j]))<D('2e-14') for j in range(2))
    expected_edges=defaultdict(list)
    for addr,(corners,poly) in neighbors.items():
        for i,(a,b) in enumerate(cyclic(corners)):
            key=tuple(sorted((a,b)))
            expected_edges[key].append((addr,expected_arrow(a,b,poly,i)))
    used=defaultdict(set);counts=Counter();shape_area={}
    for addr,c in lookup.items():
        corners,poly=kept[addr]
        assert c['base_lift']==list(corners[0]) and c['chirality']==1 and not c['isometry']['reflection']
        assert c['id'].endswith('/rhomb/'+'/'.join(map(str,addr)))
        n=c['prototype'];counts[n]+=1
        expected='thick' if addr[1]-addr[0] in (1,4) else 'thin'
        assert n==expected
        area=polygon_area(poly)
        assert abs(area-(s1 if n=='thick' else s2))<EPS
        shape_area[n]=str(area)
        assert abs(dot(v(poly[0],poly[1]),v(poly[0],poly[3]))-(c1 if n=="thick" else c2))<EPS
        for i,side in enumerate(c['boundary']):
            e=edge[side['edge']]
            start,end=(e['to'],e['from']) if side['reversed'] else (e['from'],e['to'])
            a,b=tuple(vertex[start]['lift']),tuple(vertex[end]['lift'])
            assert a==corners[i] and b==corners[(i+1)%4]
            assert abs(dot(v(poly[i],poly[(i+1)%4]),v(poly[i],poly[(i+1)%4]))-1)<EPS
            used[e['id']].add(addr)
            assert side['matching_class']==e['matching']['class']
    assert counts==cert['selected_counts']
    red=green=cuts=0
    for id_,e in edge.items():
        a,b=tuple(vertex[e['from']]['lift']),tuple(vertex[e['to']]['lift'])
        assert sum(abs(x-y) for x,y in zip(a,b))==1
        hypotheses=expected_edges[tuple(sorted((a,b)))]
        assert len(hypotheses)==2 and hypotheses[0][1]==hypotheses[1][1],id_
        assert used[id_]=={addr for addr,_ in hypotheses if addr in kept}
        world_ids=e['global_cells']
        assert {tuple(map(int,s.split('/rhomb/')[1].split('/'))) for s in world_ids}=={addr for addr,_ in hypotheses}
        assert e['global_owner']==min(world_ids)
        p=e['matching'];color,num,src,dst=hypotheses[0][1]
        assert (p['class'],p['multiplicity'])==(color,num)
        assert tuple(vertex[p['from']]['lift'])==src and tuple(vertex[p['to']]['lift'])==dst
        red+=color=='red';green+=color=='green'
        cuts+=len(used[id_])==1
        assert e['boundary_reason']==('query_cut' if len(used[id_])==1 else 'none')
    assert cuts==cert['query_cuts']
    q=tuple(map(decimal,cert['normalized_query']));region=quad(q)
    pieces=[clip(poly,region) for _,poly in kept.values() if meet(box(poly),q)]
    area=sum(map(polygon_area,pieces))
    assert abs(area-polygon_area(region))<D('1e-49'),(area,polygon_area(region))
    # For bounded interior checks, exclude disjoint bounding boxes before clipping.
    polygons=[(poly,box(poly)) for _,poly in kept.values()]
    tested=0
    for (p,pb),(r,rb) in combinations(polygons,2):
        if meet(pb,rb):
            assert polygon_area(clip(p,r))<D('1e-51')
            tested+=1
    return {'counts':dict(counts),'red_edges':red,'green_edges':green,'query_cuts':cuts,
            'area_error':str(abs(area-polygon_area(region))),'tested_overlap_pairs':tested,
            'unit_areas':shape_area},kept

def spread(folder,instance,tiles):
    views=load(folder/'spread-views.json')
    assert [v['extensions']['document']['page_number'] for v in views]==[2,3]
    assert all(v['extensions']['document']['topology_unchanged'] for v in views)
    o=tuple(map(decimal,instance['frame']['origin']))
    step=decimal(instance['extensions']['penrose']['request']['step_cm'])
    world=[]
    for view in views:
        m=view['transform'];assert m[:4]==[1,0,0,1]
        b=tuple(decimal(q)-decimal(m[4+i%2]) for i,q in enumerate(view['crop']))
        world.append(b)
    assert abs(world[0][2]-world[1][0])<D('1e-14') and world[0][1]==world[1][1]
    regions=[quad(tuple((q-o[i%2])/step for i,q in enumerate(b))) for b in world]
    crossing=[]
    for addr,(_,poly) in tiles.items():
        if all(polygon_area(clip(poly,r))>D('1e-45') for r in regions):
            crossing.append(list(addr))
    assert len(crossing)>2
    return {'world_viewports':[[str(x) for x in b] for b in world],'crossing_addresses':crossing}

def raster(folder,existing):
    from PIL import Image,ImageChops,ImageStat
    dims={'clean':(225,165),'diagnostic':(225,165),'offset':(225,195),'alternate':(225,165),
          'common-a':(150,105),'common-b':(150,105),'spread-left':(150,192),'spread-right':(150,192)}
    out={}
    for name,(w,h) in dims.items():
        a,b=[folder/f'{name}-{kind}.png' for kind in ('pdf','svg')]
        if not existing:
            subprocess.run(['pdftoppm','-r','152.4','-W',str(w),'-H',str(h),'-png','-singlefile',
                            str(folder/f'{name}.pdf'),str(a.with_suffix(''))],check=True)
            subprocess.run(['inkscape',str(folder/f'{name}.svg'),'--export-background=white',
                            '--export-background-opacity=1',f'--export-width={w}',f'--export-filename={b}'],check=True)
        images=[Image.open(p).convert('RGB') for p in (a,b)]
        assert all(i.size==(w,h) for i in images),(name,[i.size for i in images])
        mean=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
        assert mean<.06,(name,mean)
        assert all(im.getpixel((w//2,h//2))!=(255,255,255) for im in images)
        out[name]={'mean_backend_error':mean,'size':[w,h]}
    for kind in ('pdf','svg'):
        assert (folder/f'common-a.{kind}').read_bytes()==(folder/f'common-b.{kind}').read_bytes()
        images=[Image.open(folder/f'common-{c}-{kind}.png').convert('RGB') for c in ('a','b')]
        assert ImageChops.difference(*images).getbbox() is None
    return out

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--existing-rasters',action='store_true')
    args=parser.parse_args();count=0
    for folder in sorted((ROOT/'build/penrose').glob('*')):
        receipts=sorted(folder.glob('receipt-Lua-*.json'))
        if not receipts:continue
        r=load(receipts[0])
        if not all(sha((ROOT/s['path']).read_bytes().replace(b'\r\n',b'\n'))==s['sha256'] for s in r['source']):continue
        assert r['source_digest']==folder.name
        for other in receipts[1:]:assert load(other)['outputs']==r['outputs']
        for f,h in r['outputs'].items():assert sha((folder/f).read_bytes())==h,f
        data={n:load(folder/f'{n}.instance') for n in NAMES}
        audited={n:audit(x) for n,x in data.items()}
        ids={n:{c['id']:c for c in x['structures']['tiling']['cells']} for n,x in data.items()}
        assert ids['small'].keys()<ids['medium'].keys()<ids['large'].keys()
        for n in ('small','medium'):
            assert all(ids['large'][k]==c for k,c in ids[n].items())
        shared=ids['small'].keys()&ids['offset'].keys()
        assert len(shared)==r['shared'] and all(ids['small'][i]==ids['offset'][i] for i in shared)
        added=[{kind:audited[b][0]['counts'][kind]-audited[a][0]['counts'][kind] for kind in ('thick','thin')}
               for a,b in (('small','medium'),('medium','large'))]
        assert all(all(n>0 for n in c.values()) for c in added)
        result=spread(folder,data['large'],audited['large'][1])
        record=r['build_record']; assert record['status']=='complete'
        assert record['extensions']['construction']==data['large']['extensions']['penrose']['certificate']
        report={'stage':'14','source_digest':folder.name,'precision_digits':getcontext().prec,
                'queries':{n:a[0] for n,a in audited.items()},'shared_tiles':len(shared),
                'finite_expansion_counts':added,'spread':result,'same_world_view':'byte and pixel exact',
                'outputs':len(r['outputs']),'rasters':raster(folder,args.existing_rasters)}
        (folder/'oracle.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
        print('penrose_oracle: %d query rhombi, %d stable shared rhombi, %d gutter-crossing rhombi' %
              (sum(sum(x[0]['counts'].values()) for x in audited.values()),len(shared),len(result['crossing_addresses'])))
        count+=1
    assert count,'no current-source Penrose receipts'

if __name__=='__main__':
    main()

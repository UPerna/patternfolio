"""Independent source, finite-complex, and cubic edge audit for Spectres."""
from collections import Counter, defaultdict
from decimal import Decimal as D, ROUND_FLOOR, getcontext
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

getcontext().prec=70
ROOT=Path(__file__).resolve().parents[1]
EPS=D('1e-55')
sqrt3=D(3).sqrt()
V30=(sqrt3/2,D('.5'))
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(b):return hashlib.sha256(b).hexdigest()
def add(a,b):return (a[0]+b[0],a[1]+b[1])
def sub(a,b):return (a[0]-b[0],a[1]-b[1])
def mul(a,k):return (a[0]*k,a[1]*k)
def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def dot(a,b):return a[0]*b[0]+a[1]*b[1]
def cmul(a,b):return (a[0]*b[0]-a[1]*b[1],a[0]*b[1]+a[1]*b[0])
def conj(a):return (a[0],-a[1])
def near(a,b):return max(map(abs,sub(a,b)))<EPS
def turn(n):
    x=(D(1),D(0))
    for _ in range(n%12):x=cmul(x,V30)
    return x
def affine(t,p):
    a,r,b=t
    return add(cmul(a,conj(p) if r else p),b)
def compose(a,b):
    u,f,p=a;v,g,q=b
    return (cmul(u,conj(v) if f else v),f!=g,affine(a,q))
def exact(p,d=2):
    return ((p[0]+p[1]*sqrt3)/d,(p[2]+p[3]*sqrt3)/d)
def cyc(p):return zip(p,p[1:]+p[:1])
def rounded(p):
    return [int((n*1000000+D('.5')).to_integral_value(rounding=ROUND_FLOOR)) for n in p]
def source_polygon():
    steps=(0,10,1,3,0,2,5,7,4,6,6,8,11,9)
    p=(D(0),D(0));out=[]
    for n in steps:
        out.append(p);p=add(p,turn(n))
    assert near(p,(D(0),D(0)))
    return out
POLY=source_polygon()
# The published marked-cluster slot chart, indexed with descriptive names.
SLOT_TYPES={
 'Gamma':('Pi','Delta',None,'Theta','Sigma','Xi','Phi','Gamma'),
 'Delta':('Xi','Delta','Xi','Phi','Sigma','Pi','Phi','Gamma'),
 'Theta':('Psi','Delta','Pi','Phi','Sigma','Pi','Phi','Gamma'),
 'Lambda':('Psi','Delta','Xi','Phi','Sigma','Pi','Phi','Gamma'),
 'Xi':('Psi','Delta','Pi','Phi','Sigma','Psi','Phi','Gamma'),
 'Pi':('Psi','Delta','Xi','Phi','Sigma','Psi','Phi','Gamma'),
 'Sigma':('Xi','Delta','Xi','Phi','Sigma','Pi','Lambda','Gamma'),
 'Phi':('Psi','Delta','Psi','Phi','Sigma','Pi','Phi','Gamma'),
 'Psi':('Psi','Delta','Psi','Phi','Sigma','Psi','Phi','Gamma'),
}
def reference(depth,name):
    quad=[POLY[i] for i in (3,5,7,11)]
    identity=((D(1),D(0)),False,(D(0),D(0)))
    reflection=((D(-1),D(0)),True,(D(0),D(0)))  # y-axis
    chart=[]
    for _ in range(depth):
        placed=[identity]
        for absolute,left,right in zip((2,2,4,6,6,8,4),(3,2,3,3,2,3,3),(1,0,1,1,0,1,3)):
            a=turn(absolute)
            target=affine(placed[-1],quad[left])
            placed.append((a,False,sub(target,cmul(a,quad[right]))))
        placed=[compose(reflection,p) for p in placed]
        chart.append(placed)
        quad=[affine(placed[i],quad[j]) for i,j in ((6,2),(5,1),(3,2),(0,1))]
    leaves=[];nodes={}
    def walk(level,label,t,address):
        if level==0 and label!='Gamma':
            assert not t[1]
            leaves.append((address,label,t,[affine(t,p) for p in POLY]));return
        children=[]
        if level==0:
            for suffix,leaf,t1 in [('a','Gamma1',t),('b','Gamma2',compose(t,(turn(1),False,POLY[8])))]:
                a=address+suffix;children.append(a)
                assert not t1[1]
                leaves.append((a,leaf,t1,[affine(t1,p) for p in POLY]))
        else:
            for i,child in enumerate(SLOT_TYPES[label]):
                if child:
                    a=address+str(i+1);children.append(a)
                    walk(level-1,child,compose(t,chart[level-1][i]),a)
        nodes[address]=(label,level,t,children)
    walk(depth,name,reflection if depth%2 else identity,'r')
    rows=[[label,[rounded(p) for p in points]] for _,label,_,points in leaves]
    digest=sha(json.dumps(rows,separators=(',',':')).encode())
    return leaves,nodes,digest

def box(poly):
    xs,ys=zip(*poly)
    return min(xs),min(ys),max(xs),max(ys)
def meets(a,b,eps=EPS):
    return a[0]-eps<=b[2] and b[0]-eps<=a[2] and a[1]-eps<=b[3] and b[1]-eps<=a[3]
def polygon_area(p):
    return sum(cross(a,b) for a,b in cyc(p))/2
def bbox_grow(b,g):
    return (b[0]-g,b[1]-g,b[2]+g,b[3]+g)
def interval(axis,poly,origin):
    values=[cross(axis,sub(p,origin)) for p in poly]
    return min(values),max(values)
def separated(a,b,shared):
    for hull in (a,b):
        for p,q in cyc(hull):
            axis=sub(q,p)
            alo,ahi=interval(axis,a,p);blo,bhi=interval(axis,b,p)
            if ahi<blo-EPS or bhi<alo-EPS:return True
            if shared and (abs(ahi-blo)<EPS or abs(bhi-alo)<EPS):return True
    return False

def cubic_area(a,b,c,d):
    # Twice signed area integral of x dy - y dx, then divide by two.
    co=[a,mul(sub(b,a),3),mul(add(sub(c,mul(b,2)),a),3),
        sub(add(sub(d,mul(c,3)),mul(b,3)),a)]
    return sum(cross(co[i],co[j])*j/D(i+j) for i in range(4) for j in range(1,4))/2

def geometry_key(p):
    # Reference decimal values represent exact quadratic points. This key
    # is only for independent audit incidence and is never used by runtime.
    return tuple(int((v*D(10)**40+D('.5')).to_integral_value(rounding=ROUND_FLOOR)) for v in p)

def edge_geometry(a,b):
    d=sub(b,a);normal=(-d[1],d[0])
    c1=add(add(a,mul(d,D(1)/3)),mul(normal,D(1)/16))
    c2=sub(add(a,mul(d,D(2)/3)),mul(normal,D(1)/16))
    return c1,c2
def edge_pair(a,b):return tuple(sorted((geometry_key(a),geometry_key(b))))
def root_complex(leaves):
    edges={}
    for address,_,_,poly in leaves:
        assert abs(polygon_area(poly)-(3+3*sqrt3))<EPS
        for a,b in cyc(poly):
            key=edge_pair(a,b)
            edges.setdefault(key,[]).append((address,a,b))
    boundary=shared=0;area=D(0);hulls=[];max_cubic=D(0)
    for key,uses in edges.items():
        _,a,b=uses[0]
        if len(uses)==1:
            boundary+=1;area+=cross(a,b)/2
        else:
            assert len(uses)==2 and near(a,uses[1][2]) and near(b,uses[1][1])
            shared+=1
        c1,c2=edge_geometry(a,b)
        residual=abs(cubic_area(a,c1,c2,b)-cross(a,b)/2)
        max_cubic=max(max_cubic,residual)
        assert residual<EPS
        hull=(a,c2,b,c1);hulls.append((box(hull),hull,key))
    assert abs(area-len(leaves)*(3+3*sqrt3))<EPS
    hulls.sort(key=lambda h:h[0][0]);pairs=0
    pad=D('1e-10')
    for i,(a,p,k) in enumerate(hulls):
        for b,q,j in hulls[i+1:]:
            if b[0]>a[2]+pad:break
            if meets(a,b,pad):
                assert separated(p,q,bool(set(k)&set(j))),(k,j)
                pairs+=1
    return edges,{'root_boundary_edges':boundary,'root_shared_edges':shared,'hull_pairs':pairs,
                  'maximum_cubic_signed_area_error':str(max_cubic)}

def audit(instance,reference_data,geometry):
    leafs,nodes,digest=reference_data
    edges,proof=geometry
    ext=instance['extensions']['spectre']; req=ext['request'];cert=ext['certificate']
    curved=req['boundary']=='spectre-s'
    assert cert['strictly_chiral']==curved
    assert cert['geometry_case']==('strictly_chiral_s_curve_spectre' if curved else 'weakly_chiral_tile_1_1_diagnostic')
    assert cert['root_leaf_count']==len(leafs) and cert['reference_coordinate_digest']==digest
    assert all(cert['root_complex'][k]==v for k,v in proof.items() if k!='maximum_cubic_signed_area_error')
    assert abs((cert['unit_area']['rational']+cert['unit_area']['radical']*sqrt3)/cert['unit_area']['denominator']-(3+3*sqrt3))<EPS
    assert cert['root_complex']['root_area']['rational']==cert['unit_area']['rational']*len(leafs)
    assert cert['root_complex']['root_area']['radical']==cert['unit_area']['radical']*len(leafs)
    origin=tuple(D(str(x)) for x in req['frame']['origin']);step=D(str(req['step_cm']))
    q=tuple((D(str(x))-origin[i%2])/step for i,x in enumerate(req['world_query']))
    expanded=bbox_grow(q,D(str(req['halo'])))
    expected={a for a,_,_,poly in leafs if req['whole_root'] or meets(box(poly),expanded,D('.063'))}
    tiling=instance['structures']['tiling']
    cells={c['address']:c for c in tiling['cells']}
    assert len(cells)==len(expected)==cert['selected_leaf_count'] and cells.keys()==expected
    vertices={p['id']:p for p in tiling['vertices']}
    rendered={p['id']:exact(p['lattice']) for p in vertices.values()}
    for id_,p in vertices.items():
        assert id_.endswith('/v/'+'/'.join(map(str,p['lattice'])))
        target=add(origin,mul(rendered[id_],step))
        assert max(abs(D(str(q))-r) for q,r in zip(p['point'],target))<D('1e-10')
    e_map={e['id']:e for e in tiling['edges']}
    incidence=defaultdict(set)
    ancestors={a[:i] for a in expected for i in range(1,len(a))}
    for i,(a,label,t,poly) in enumerate(leafs,1):
        if a not in cells:continue
        c=cells[a]
        assert c['lineage_label']==label and c['reference_ordinal']==i
        assert c['id'].endswith('/tile/'+a) and c['parent'].endswith('/cluster/'+a[:-1])
        assert c['chirality']==1 and not c['exact_transform']['reflected'] and not c['isometry']['reflection']
        assert near(exact(c['exact_transform']['offset']),t[2])
        assert near(turn(c['exact_transform']['turn']),t[0])
        assert len(c['boundary'])==14
        for j,(p,q) in enumerate(cyc(poly)):
            use=c['boundary'][j];assert use['prototype_edge']==j+1
            e=e_map[use['edge']]
            s,d=(e['to'],e['from']) if use['reversed'] else (e['from'],e['to'])
            assert near(p,rendered[s]) and near(q,rendered[d])
            assert abs(dot(sub(q,p),sub(q,p))-1)<EPS
            incidence[e['id']].add(a)
    cuts=0
    for id_,e in e_map.items():
        a,b=rendered[e['from']],rendered[e['to']]
        uses=edges[edge_pair(a,b)]
        all_addresses={t[0] for t in uses}
        assert {x.rsplit('/',1)[-1] for x in e['global_cells']}==all_addresses
        assert e['global_owner']==min(e['global_cells'])
        assert incidence[id_]==all_addresses&expected
        reason='none' if len(incidence[id_])==2 else 'root_boundary' if len(uses)==1 else 'query_cut'
        assert e['boundary_reason']==reason
        cuts+=reason=='query_cut'
        if curved:
            c=e['curve']
            assert c['kind']=='centrally_symmetric_cubic' and c['denominator']==192
            c1,c2=exact(c['control1'],192),exact(c['control2'],192)
            p,q=edge_geometry(a,b)
            assert near(c1,p) and near(c2,q) and near(add(c1,c2),add(a,b))
            d1,d2=edge_geometry(b,a)
            assert near(c1,d2) and near(c2,d1)
        else:
            assert 'curve' not in e
    assert cuts==cert['query_cuts']
    assert {n['address'] for n in tiling['hierarchy']}==ancestors
    for n in tiling['hierarchy']:
        label,level,t,children=nodes[n['address']]
        assert n['type']==label and n['level']==level
        x=n['exact_transform'];assert x['reflected']==t[1] and near(mul(turn(x['turn']),-1 if x['reflected'] else 1),t[0]) and near(exact(x['offset']),t[2])
        assert [x.rsplit('/',1)[-1] for x in n['source_children']]==children
        assert [x.rsplit('/',1)[-1] for x in n['children']]==[a for a in children if a in expected|ancestors]
    return {'leaves':len(cells),'edges':len(e_map),'query_cuts':cuts,'curved':curved,
            'root_complex':proof,'lineage_count':len(ancestors)}

VIEWS={
 'curved':(462,453,152.4),'straight':(462,453,152.4),'crop-a':(189,252,152.4),
 'crop-b':(237,186,152.4),'common-a':(93,138,152.4),'common-b':(93,138,152.4),
 'detail-curved':(300,260,508),'detail-straight':(300,260,508),'deep':(222,150,152.4),
}
def raster(folder,existing):
    from PIL import Image,ImageChops,ImageStat
    out={}
    for name,(w,h,dpi) in VIEWS.items():
        a,b=[folder/f'{name}-{kind}.png' for kind in ('pdf','svg')]
        if not existing:
            subprocess.run(['pdftoppm','-r',str(dpi),'-W',str(w),'-H',str(h),'-png','-singlefile',
                            str(folder/f'{name}.pdf'),str(a.with_suffix(''))],check=True)
            subprocess.run(['inkscape',str(folder/f'{name}.svg'),'--export-background=white',
                            '--export-background-opacity=1',f'--export-width={w}',f'--export-filename={b}'],check=True)
        images=[Image.open(p).convert('RGB') for p in (a,b)]
        assert all(i.size==(w,h) for i in images),(name,[i.size for i in images])
        mean=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
        ink=[sum(i.convert('L').histogram()[:220]) for i in images]
        assert mean<.06 and min(ink)>100,(name,mean,ink)
        out[name]={'mean_backend_error':mean,'size':[w,h],'ink_pixels':ink}
    for kind in ('pdf','svg'):
        assert (folder/f'common-a.{kind}').read_bytes()==(folder/f'common-b.{kind}').read_bytes()
        ims=[Image.open(folder/f'common-{x}-{kind}.png').convert('RGB') for x in ('a','b')]
        assert ImageChops.difference(*ims).getbbox() is None
        images=[Image.open(folder/f'detail-{x}-{kind}.png').convert('RGB') for x in ('curved','straight')]
        diff=ImageChops.difference(*images)
        assert diff.getbbox() is not None
        out['detail-curved']['curved_vs_straight_'+kind]=sum(ImageStat.Stat(diff).mean)/(3*255)
    return out

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--existing-rasters',action='store_true')
    args=parser.parse_args();count=0
    fixture=read(ROOT/'docs/validation/fixtures/spectre-reference-hashes.json')
    cache={}
    for record in fixture:
        key=(record['depth'],record['name'])
        data=reference(*key)
        assert data[2]==record['digest'] and len(data[0])==record['count'],key
        cache[key]=(data,root_complex(data[0]))
    for folder in sorted((ROOT/'build/spectre').glob('*')):
        receipts=sorted(folder.glob('receipt-Lua-*.json'))
        if not receipts:continue
        r=read(receipts[0])
        if not all(sha((ROOT/s['path']).read_bytes().replace(b'\r\n',b'\n'))==s['sha256'] for s in r['source']):continue
        assert r['source_digest']==folder.name
        for other in receipts[1:]:assert read(other)['outputs']==r['outputs']
        for f,h in r['outputs'].items():assert sha((folder/f).read_bytes())==h,f
        for actual,expected in zip(r['references'],fixture):
            key=(expected['depth'],expected['name'])
            assert actual['count']==expected['count'] and actual['digest']==expected['digest']
            assert all(actual['proof'][k]==v for k,v in cache[key][1][1].items()
                       if k!='maximum_cubic_signed_area_error')
        cases={n:read(folder/f'{n}.instance') for n in ('curved','straight','a','b','deep')}
        results={}
        for n,x in cases.items():
            req=x['extensions']['spectre']['request']
            results[n]=audit(x,*cache[req['depth'],req['root']])
        ids={n:{c['id']:c for c in x['structures']['tiling']['cells']} for n,x in cases.items()}
        assert ids['curved']==ids['straight']
        assert all(ids['curved'][k]==v for n in ('a','b') for k,v in ids[n].items())
        shared=ids['a'].keys()&ids['b'].keys()
        assert len(shared)==r['shared'] and all(ids['a'][k]==ids['b'][k] for k in shared)
        assert r['build_record']['status']=='complete'
        assert r['build_record']['extensions']['construction']==cases['a']['extensions']['spectre']['certificate']
        report={'stage':'15','source_digest':folder.name,'precision_digits':getcontext().prec,
                'reference_roots':[{**r,'independent_proof':cache[r['depth'],r['name']][1][1]} for r in fixture],
                'fixtures':results,'shared_tiles':len(shared),'same_world_view':'byte and pixel exact',
                'outputs':len(r['outputs']),'rasters':raster(folder,args.existing_rasters)}
        (folder/'oracle.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
        print('spectre_oracle: five reference roots, %d stable shared leaves and exact common views'%len(shared))
        count+=1
    assert count,'no current-source Spectre receipts'

if __name__=='__main__':
    main()

"""Independent integer audit of the finite chair substitution and its queries."""
from collections import defaultdict
from itertools import combinations
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]
SQUARES={(0,0),(1,0),(0,1)}
ROTATIONS=((1,0,0,1),(0,-1,1,0),(-1,0,0,-1),(0,1,-1,0))
def load(p):return json.loads(p.read_text(encoding='utf8'))
def sha(b):return hashlib.sha256(b).hexdigest()
def point(p,t):
    a,b,c,d=ROTATIONS[t['turn']]
    s=t['scale'];u,v=t['offset'];x,y=p
    return (u+s*(a*x+b*y),v+s*(c*x+d*y))
def squares(t):
    cells=set()
    for x,y in SQUARES:
        points=[point((x+i,y+j),t) for i,j in ((0,0),(1,0),(1,1),(0,1))]
        xs,ys=zip(*points)
        cells.update((i,j) for i in range(min(xs),max(xs)) for j in range(min(ys),max(ys)))
    return cells
def infer_dissection():
    root={(x,y) for x in range(4) for y in range(4) if min(x,y)<2}
    fits=[]
    for turn in range(4):
        for x in range(-2,7):
            for y in range(-2,7):
                t={'turn':turn,'offset':[x,y],'scale':1,'chirality':1}
                p=squares(t)
                if p<=root:fits.append((t,p))
    result=[]
    for ts in combinations(fits,4):
        if set().union(*(p for t,p in ts))==root:
            result.append([t for t,p in ts])
    assert len(result)==1
    return result[0]
def compose(parent,child):
    s=parent['scale']//2
    a,b,c,d=ROTATIONS[parent['turn']]
    x,y=child['offset'];u,v=parent['offset']
    return {'offset':[u+s*(a*x+b*y),v+s*(c*x+d*y)],'scale':s,
            'turn':(parent['turn']+child['turn'])%4,'chirality':1}
def all_transforms(depth):
    children=infer_dissection()
    forest={'r':{'offset':[0,0],'turn':0,'scale':2**depth,'chirality':1}}
    for _ in range(depth):
        pending=[(k,t) for k,t in forest.items() if t['scale']>1 and k+'a' not in forest]
        for k,t in pending:
            for n,ch in zip('abcd',children):forest[k+n]=compose(t,ch)
    return forest
def sq_edges(cells):
    edges=set()
    for x,y in cells:
        corners=[(x,y),(x+1,y),(x+1,y+1),(x,y+1)]
        for a,b in zip(corners,corners[1:]+corners[:1]):
            if (b,a) in edges:edges.remove((b,a))
            else:edges.add((a,b))
    return edges
def overlap(p,b):
    x,y=p
    return x<b[2] and y<b[3] and x+1>b[0] and y+1>b[1]

def audit(x,forest,whole):
    e=x['extensions']['substitution'];certificate=e['certificate'];request=e['request']
    t=x['structures']['tiling']
    depth=certificate['depth'];side=2**depth;origin=request['frame']['origin'];step=request['step_cm']
    assert certificate['lattice_horizon']==[[0,0,2*side,side],[0,side,side,2*side]]
    assert certificate['finite'] is True and certificate['globally_queryable'] is False
    assert request['whole_root']==whole
    assert e['capabilities']['hierarchical_substitution']['implemented']
    assert not e['capabilities']['projection_multigrid']['implemented']
    assert not e['capabilities']['bounded_constraint']['implemented']
    q=[(v-origin[i%2])/step for i,v in enumerate(request['world_query'])]
    assert certificate['query']==q
    halo=certificate['halo_lattice_units'];assert halo>=3
    expanded=[q[0]-halo,q[1]-halo,q[2]+halo,q[3]+halo]
    leafsets={a:squares(v) for a,v in forest.items() if v['scale']==1}
    occupied=set().union(*leafsets.values())
    assert len(occupied)==sum(map(len,leafsets.values()))==certificate['root_unit_square_count']
    assert occupied=={(i,j) for i in range(2*side) for j in range(2*side) if min(i,j)<side}
    if not whole:
        assert 0<=q[0]<q[2]<=2*side and 0<=q[1]<q[3]<=2*side and (q[2]<=side or q[3]<=side)
    expected={a for a,pts in leafsets.items() if whole or any(overlap(p,expanded) for p in pts)}
    assert certificate['query_leaf_count']==sum(any(overlap(p,q) for p in pts) for pts in leafsets.values())
    assert certificate['selected_leaf_count']==len(expected)==len(t['cells'])
    addresses={c['address']:c for c in t['cells']}
    assert addresses.keys()==expected
    vertices={v['id']:tuple(v['lattice']) for v in t['vertices']}
    edges={e['id']:e for e in t['edges']}
    actual_incidence=defaultdict(set)
    for v in t['vertices']:
        i,j=v['lattice']
        assert v['point']==[origin[0]+i*step,origin[1]+j*step]
        assert v['id'].endswith(f'/v/{i}/{j}')
    for address,c in addresses.items():
        tr=forest[address]
        assert c['exact_transform']==tr and c['chirality']==1 and c['prototype']=='chair/unit'
        assert c['id'].endswith('/tile/'+address) and c['parent'].endswith('/supertile/'+address[:-1])
        assert {(s[0],s[1]) for s in c['squares']}==leafsets[address]
        assert all(s[2]==s[0]+1 and s[3]==s[1]+1 for s in c['squares'])
        assert c['isometry']=={'reflection':False,'rotation_degrees':90*tr['turn'],
                              'translation':[origin[i]+step*tr['offset'][i] for i in (0,1)]}
        directed=[]
        for side in c['boundary']:
            e0=edges[side['edge']]
            a,b=vertices[e0['from']],vertices[e0['to']]
            directed.append((b,a) if side['reversed'] else (a,b))
            actual_incidence[e0['id']].add(c['id'])
        assert len(directed)==8 and set(directed)==sq_edges(leafsets[address])
        assert all(a[1]==b[0] for a,b in zip(directed,directed[1:]+directed[:1]))
    global_edges=defaultdict(set)
    for addr,pts in leafsets.items():
        for a,b in sq_edges(pts):global_edges[tuple(sorted((a,b)))].add(addr)
    cuts=0
    for id_,edge in edges.items():
        a,b=vertices[edge['from']],vertices[edge['to']]
        key=tuple(sorted((a,b)))
        parents=global_edges[key];present=parents&expected
        assert len(parents) in (1,2)
        assert {i.rsplit('/',1)[1] for i in edge['global_cells']}==parents
        assert {i.rsplit('/',1)[1] for i in actual_incidence[id_]}==present
        assert edge['global_owner']==min(edge['global_cells'])
        assert edge['owner']==min(actual_incidence[id_])
        reason='none' if len(present)==2 else 'root_boundary' if len(parents)==1 else 'query_cut'
        assert edge['boundary_reason']==reason
        cuts+=reason=='query_cut'
    ancestors={a[:i] for a in expected for i in range(1,len(a))}
    assert ancestors=={n['address'] for n in t['hierarchy']}
    for node in t['hierarchy']:
        a=node['address'];tr=forest[a]
        assert node['exact_transform']==tr and node['level']==tr['scale'].bit_length()-1
        full={a+n for n in 'abcd'}
        assert {i.rsplit('/',1)[1] for i in node['substitution_children']}==full
        assert {i.rsplit('/',1)[1] for i in node['children']}==full&(expected|ancestors)
    return {'leaves':len(addresses),'edges':len(edges),'query_cuts':cuts,'ancestors':len(ancestors)}

def raster(folder,existing):
    from PIL import Image,ImageChops,ImageStat
    dims={'root':(480,480),'a':(165,135),'common-a':(60,75),'common-b':(60,75)}
    result={}
    for name,(w,h) in dims.items():
        a,b=[folder/f'{name}-{kind}.png' for kind in ('pdf','svg')]
        if not existing:
            subprocess.run(['pdftoppm','-r','152.4','-W',str(w),'-H',str(h),'-png','-singlefile',
                            str(folder/f'{name}.pdf'),str(a.with_suffix(''))],check=True)
            subprocess.run(['inkscape',str(folder/f'{name}.svg'),'--export-background=white',
                            '--export-background-opacity=1',f'--export-width={w}',f'--export-filename={b}'],check=True)
        images=[Image.open(p).convert('RGB') for p in (a,b)]
        assert all(i.size==(w,h) for i in images),(name,[i.size for i in images])
        err=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
        assert err<.065,(name,err)
        if name=='root':
            for im in images:
                assert im.getpixel((420,60))==(255,255,255)
                assert im.getpixel((420,420))!=(255,255,255)
                assert im.getpixel((60,60))!=(255,255,255)
        else:
            for im in images:
                assert all(im.getpixel(p)!=(255,255,255) for p in ((5,5),(w//2,h//2),(w-5,h-5)))
        result[name]={'mean_backend_error':err,'size':[w,h]}
    for kind in ('pdf','svg'):
        assert (folder/f'common-a.{kind}').read_bytes()==(folder/f'common-b.{kind}').read_bytes()
        ims=[Image.open(folder/f'common-{letter}-{kind}.png').convert('RGB') for letter in ('a','b')]
        assert ImageChops.difference(*ims).getbbox() is None
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--existing-rasters',action='store_true')
    args=parser.parse_args();count=0
    for folder in sorted((ROOT/'build/substitution').glob('*')):
        receipts=sorted(folder.glob('receipt-Lua-*.json'))
        if not receipts:continue
        r=load(receipts[0])
        if not all(sha((ROOT/s['path']).read_bytes().replace(b'\r\n',b'\n'))==s['sha256'] for s in r['source']):continue
        assert r['source_digest']==folder.name
        for other in receipts[1:]:assert load(other)['outputs']==r['outputs']
        for f,h in r['outputs'].items():assert sha((folder/f).read_bytes())==h,f
        names=('root','a','b','expanded')
        instances={n:load(folder/f'{n}.instance') for n in names}
        forest=all_transforms(4)
        results={n:audit(x,forest,n=='root') for n,x in instances.items()}
        sets={n:{t['id']:t for t in x['structures']['tiling']['cells']} for n,x in instances.items()}
        shared=sets['a'].keys()&sets['b'].keys()
        assert len(shared)==r['shared']==64
        assert sets['a'].keys()<=sets['expanded'].keys()
        for n,cells in sets.items():
            assert all(t==sets['root'][i] for i,t in cells.items()),n
        assert results['a']['query_cuts']==r['query_cuts']
        record=r['build_record']; c=record['extensions']['construction']
        assert record['status']=='complete' and c==instances['a']['extensions']['substitution']['certificate']
        assert len(c['checks'])==6 and c['root_unit_square_count']==768
        report={'stage':'13','source_digest':folder.name,'finite_root':{'leaves':256,'unit_squares':768},
                'queries':results,'shared_leaves':len(shared),'outputs':len(r['outputs']),
                'same_world_view':'byte and pixel exact','rasters':raster(folder,args.existing_rasters)}
        (folder/'oracle.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
        print('substitution_oracle: 768 covered unit squares, 256 leaves, 64 stable shared leaves, and exact common views')
        count+=1
    assert count,'no current-source substitution receipts'

if __name__=='__main__':
    main()

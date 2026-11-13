"""Independent audit of circle packing, decoded patch, and rendered motif seams."""
import argparse
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path
import hashlib
import json
import math
import subprocess

ROOT=Path(__file__).resolve().parents[1]
NAMES=('base','mixed','panel')
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(b):return hashlib.sha256(b).hexdigest()
def v(a,b):return (b[0]-a[0],b[1]-a[1])
def dot(a,b):return a[0]*b[0]+a[1]*b[1]
def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def midpoint(a,b):return tuple((x+y)/2 for x,y in zip(a,b))
def unit(a):
    n=math.hypot(*a)
    return (a[0]/n,a[1]/n)
def adjacent(xs):return zip(xs,xs[1:]+xs[:1])

def packing(record):
    c=record['circles']; faces=record['complex']['faces'];normal=record['normalization']
    scale=normal['scale'];tol=record['tolerance'];epsilon=120*scale*tol+1e-12
    assert record['converged'] and record['solver']=='disk-angle-bisection-v1'
    boundary=set();degrees=Counter();g=Counter();angle=defaultdict(list);radius_angles=defaultdict(list)
    for f in faces:
        assert len(set(f))==3
        centers=[c[k]['center'] for k in f]
        assert cross(v(centers[0],centers[1]),v(centers[0],centers[2]))>0
        for i,a in enumerate(f):
            b,d=f[(i+1)%3],f[i-1]
            g[tuple(sorted((a,b)))]+=1
            ab=v(c[a]['center'],c[b]['center']);ad=v(c[a]['center'],c[d]['center'])
            angle[a].append(math.atan2(abs(cross(ab,ad)),dot(ab,ad)))
            ri,rj,rk=[c[z]['radius'] for z in (a,b,d)]
            u,w,opposite=ri+rj,ri+rk,rj+rk
            radius_angles[a].append(math.acos(max(-1,min(1,(u*u+w*w-opposite*opposite)/(2*u*w)))))
    assert len(c)-len(g)+len(faces)==1
    for (a,b),n in g.items():
        assert n in (1,2)
        degrees[a]+=1;degrees[b]+=1
        if n==1:boundary.update((a,b))
    assert set(c)==set(degrees)
    for i,p in c.items():
        assert p['degree']==degrees[i] and p['boundary']==(i in boundary)
        assert all(map(math.isfinite,(*p['center'],p['radius']))) and p['radius']>0
        if i in boundary:
            expected=scale*(1/math.sin(math.pi/(2*degrees[i]-2))-1)
            assert abs(expected-p['radius'])<epsilon
        if 'panel' in normal:
            x,y=p['center'];r=p['radius'];a,b,d,e=normal['panel']
            assert a-epsilon<=x-r<x+r<=d+epsilon and b-epsilon<=y-r<y+r<=e+epsilon
    a,b=normal['root']
    assert normal['root']==faces[0][:2]
    assert math.dist(c[a]['center'],normal['translation'])<epsilon
    assert abs(c[a]['center'][1]-c[b]['center'][1])<epsilon and c[a]['center'][0]<c[b]['center'][0]
    errors=[];nonedges=[]
    for a,b in combinations(sorted(c),2):
        A,B=c[a],c[b]
        gap=math.dist(A['center'],B['center'])-A['radius']-B['radius']
        (errors if (a,b) in g else nonedges).append(abs(gap) if (a,b) in g else gap)
    assert max(errors)<=epsilon and abs(max(errors)-record['maximum_tangency_residual'])<1e-12
    assert min(nonedges)>epsilon and abs(min(nonedges)-record['minimum_nonedge_clearance'])<1e-12
    angular=max(abs(sum(angle[k])-math.tau) for k in c if k not in boundary)
    assert angular<=tol*4+1e-12
    intrinsic=max(abs(sum(radius_angles[k])-math.tau) for k in c if k not in boundary)
    assert intrinsic<=tol+1e-14 and abs(intrinsic-record["maximum_angular_residual"])<1e-14
    return {'circles':len(c),'tangencies':len(g),'maximum_tangency_residual':max(errors),
            'minimum_nonedge_clearance':min(nonedges),'maximum_embedded_angle_residual':angular,'intrinsic_angle_residual':intrinsic}

def independent_patch(k):
    patch=k['patch'];faces={f['id']:f for f in patch['faces']}
    vertices=patch['vertices']; pack=k['packing'];circles=pack['circles'];tau=k['tau']
    triangles=pack['complex']['faces'];eps=1e-9
    assert len(faces)==sum(not q['boundary'] for q in circles.values())+3*len(triangles)
    edges=defaultdict(list);polygons={}
    for id_,f in faces.items():
        cycle=f['vertices'];poly=[vertices[i] for i in cycle];polygons[id_]=poly
        for a,b in adjacent(cycle):
            edges[tuple(sorted((a,b)))].append((id_,a,b))
        assert all(cross(v(a,b),v(a,p))>=-eps for a,b in adjacent(poly) for p in poly)
        if f['kind']=='cyclic':
            c=circles[f['circle']]
            assert len(poly)==2*c['degree'] and not c['boundary']
            assert all(abs(math.dist(p,c['center'])-tau*c['radius'])<eps for p in poly)
            for i,id_v in enumerate(cycle):
                if id_v.startswith('t/'):
                    _,a,b=id_v.split('/')
                    assert a==f['circle']
                    assert abs(cross(v(c['center'],poly[i]),v(c['center'],circles[b]['center'])))<eps
                else:
                    left,right=poly[i-1],poly[(i+1)%len(poly)]
                    assert abs(math.dist(poly[i],left)-math.dist(poly[i],right))<eps
        else:
            assert len(poly)==5
            tri=f['triangle'];A,B,C=[circles[i]['center'] for i in triangles[tri-1]]
            ab,bc,ca=math.dist(A,B),math.dist(B,C),math.dist(C,A)
            expected=tuple((bc*a+ca*b+ab*c)/(ab+bc+ca) for a,b,c in zip(A,B,C))
            assert math.dist(vertices['incenter/'+str(tri)],expected)<eps
    assert len(edges)==len(patch['edges'])
    for (a,b),seq in edges.items():
        assert len(seq) in (1,2)
        assert set(patch['edges'][a+'+'+b]['faces'])=={f for f,_,_ in seq}
        if len(seq)==2:assert seq[0][1:]==seq[1][1:][::-1]
    for (i,p),(j,q) in combinations(polygons.items(),2):
        # Separating axes distinguish positive area overlap from permitted contact.
        separated=False
        for a,b in list(adjacent(p))+list(adjacent(q)):
            x,y=unit(v(a,b));normal=(-y,x)
            u=[dot(z,normal) for z in p];w=[dot(z,normal) for z in q]
            if max(u)<=min(w)+eps or max(w)<=min(u)+eps:
                separated=True;break
        assert separated,(i,j)
    return faces,vertices,edges

def ornament(instance):
    k=instance['extensions']['freeform']
    result=packing(k['packing'])
    faces,vertices,scaffold_edges=independent_patch(k)
    used={v for f in faces.values() for v in f['vertices']}
    assert len(used)-len(scaffold_edges)+len(faces)==1
    graph=instance['structures']['graph']
    nodes={v['id']:v['point'] for v in graph['vertices']}
    contacts={p['id']:p for p in k['contacts']}
    degree=Counter();linked=defaultdict(list);bends=defaultdict(list)
    for e in graph['edges']:
        a,b=e['from'],e['to']
        degree[a]+=1;degree[b]+=1
        contact,bend=(a,b) if a in contacts else (b,a)
        assert contact in contacts and bend.startswith('bend/')
        f=e['face'];poly=[vertices[i] for i in faces[f]['vertices']]
        assert all(cross(v(a,b),v(a,nodes[bend]))>=-1e-9 for a,b in adjacent(poly))
        linked[contact].append((f,unit(v(nodes[contact],nodes[bend]))))
        bends[bend].append((f,contact))
    assert set(linked)==set(contacts) and set(degree)==set(nodes)
    max_seam=0;joined=0
    for id_,p in contacts.items():
        a,b=p['scaffold_edge'].split('+')
        assert math.dist(nodes[id_],midpoint(vertices[a],vertices[b]))<1e-10
        use=linked[id_]
        assert len(use)==degree[id_]==len(p['faces'])==len(scaffold_edges[a,b])
        assert {f for f,_ in use}==set(p['faces'])
        if len(use)==2:
            joined+=1
            error=math.hypot(*(x+y for x,y in zip(use[0][1],use[1][1])))
            max_seam=max(max_seam,error)
            assert error<1e-8
    orders=[]
    for bend,uses in bends.items():
        assert degree[bend]==2 and uses[0][0]==uses[1][0]
        name=uses[0][0]
        if name not in k['wheels']:continue
        wheel=k['wheels'][name]; c=k['packing']['circles'][wheel['circle']]
        n=wheel['order'];h=math.pi/n;theta=math.radians(k['contact_angle'])
        alpha=1-2*math.sin(h)*math.cos(h)*math.sin(theta-h)/math.cos(2*h-theta)
        assert abs(alpha-wheel['alpha'])<1e-14
        expected=alpha*k['tau']*c['radius']*math.cos(h)
        assert abs(math.dist(nodes[bend],c['center'])-expected)<1e-9
        A,B=[nodes[t[1]] for t in uses]
        assert abs(math.dist(A,nodes[bend])-math.dist(B,nodes[bend]))<1e-9
        ring=faces[name]['vertices']
        edge_ids=['+'.join(sorted((a,b))) for a,b in adjacent(ring)]
        i,j=[edge_ids.index(contacts[t[1]]['scaffold_edge']) for t in uses]
        assert (j-i)%n in (2,n-2)
    panel=k['packing']['normalization']['panel']
    for point in list(nodes.values())+[vertices[i] for i in used]:
        assert all(panel[i]-1e-9<=point[i]<=panel[i+2]+1e-9 for i in (0,1))
    assert all(panel[i]+.013<=point[i]<=panel[i+2]-.013 for point in nodes.values() for i in (0,1))
    orders=sorted(x['order'] for x in k['wheels'].values())
    result.update({'orders':orders,'faces':len(faces),'joined_ports':joined,'seam_direction_residual':max_seam})
    return result

def raster(folder,existing):
    from PIL import Image,ImageChops,ImageStat
    result={}
    for name in NAMES:
        a,b=[folder/f'{name}-{kind}.png' for kind in ('pdf','svg')]
        if not existing:
            subprocess.run(['pdftoppm','-r','152.4','-W','360','-H','360','-png','-singlefile',
                            str(folder/f'{name}.pdf'),str(a.with_suffix(''))],check=True)
            subprocess.run(['inkscape',str(folder/f'{name}.svg'),'--export-background=white',
                            '--export-background-opacity=1','--export-width=360',f'--export-filename={b}'],check=True)
        images=[Image.open(p).convert('RGB') for p in (a,b)]
        assert all(i.size==(360,360) for i in images)
        ink=[sum(i.convert('L').histogram()[:210]) for i in images]
        error=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/(3*255)
        assert min(ink)>200 and max(ink)<.2*360**2 and error<.02,(name,ink,error)
        result[name]={'ink_pixels':ink,'mean_normalized_error':error}
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--existing-rasters',action='store_true')
    args=parser.parse_args();count=0
    for folder in sorted((ROOT/'build/freeform').glob('*')):
        receipts=sorted(folder.glob('receipt-Lua-*.json'))
        if not receipts:continue
        r=read(receipts[0])
        if not all(sha((ROOT/s['path']).read_bytes().replace(b'\r\n',b'\n'))==s['sha256'] for s in r['source']):continue
        assert r['source_digest']==folder.name
        for other in receipts[1:]:assert read(other)['outputs']==r['outputs']
        for f,h in r['outputs'].items():assert sha((folder/f).read_bytes())==h,f
        instances={name:read(folder/f'{name}.instance') for name in NAMES}
        results={name:ornament(x) for name,x in instances.items()}
        assert results['base']['orders']==[12] and results['mixed']['orders']==results['panel']['orders']==[6,14]
        replay=read(folder/'panel-replay.instance')
        assert replay['structures']==instances['panel']['structures']
        assert replay['extensions']['freeform']['route']=='replayed'
        p=r['build_records']['panel'];solver=p['extensions']['solver']
        assert p['status']=='complete' and solver['route']=='replayed'
        assert abs(solver['maximum_tangency_residual']-results['panel']['maximum_tangency_residual'])<1e-12
        sensitivity=[packing(x) for x in read(folder/'tolerances.json')]
        assert sensitivity[0]['maximum_tangency_residual']>sensitivity[-1]['maximum_tangency_residual']
        report={'stage':'12','source_digest':folder.name,'fixtures':results,'tolerance_sensitivity':sensitivity,
                'outputs':len(r['outputs']),'raster':raster(folder,args.existing_rasters)}
        (folder/'oracle.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
        print('freeform_oracle: %d continuous ports, %d solved circles' %
              (sum(r['joined_ports'] for r in results.values()),sum(r['circles'] for r in results.values())))
        count+=1
    assert count,'no current-source freeform receipts'

if __name__=='__main__':
    main()

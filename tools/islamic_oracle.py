"""Independent geometry and continuity checks for the Euclidean PIC fixtures."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
NAMES=('square','hexagonal','mixed','displaced','rosette','parquet')
def read(p): return json.loads(p.read_text(encoding='utf8'))
def sha(b): return hashlib.sha256(b).hexdigest()
def vec(a,b): return (b[0]-a[0],b[1]-a[1])
def cross(a,b): return a[0]*b[1]-a[1]*b[0]
def dot(a,b): return a[0]*b[0]+a[1]*b[1]
def mid(a,b): return ((a[0]+b[0])/2,(a[1]+b[1])/2)
def distance(a,b): return math.dist(a,b)
def area(p): return sum(cross(a,b) for a,b in zip(p,p[1:]+p[:1]))/2

def audit(x,name):
    p=x['extensions']['pic']
    faces={f['id']:f for f in p['scaffold_faces']}
    vertices=p['scaffold_vertices']
    g=x['structures']['graph']
    nodes={v['id']:v['point'] for v in g['vertices']}
    ports={c['id']:c for c in p['contacts']}
    delta=p['displacement']
    usage=defaultdict(list); bends=defaultdict(list); degree=Counter()
    neighbors=defaultdict(list)
    for f in faces.values():
        cycle=f['vertices']
        assert area([vertices[i] for i in cycle])>0
        for a,b in zip(cycle,cycle[1:]+cycle[:1]):
            # Both half-rays share the underlying contact edge, even at delta zero.
            neighbors[tuple(sorted((a,b)))].append((f['id'],a,b))
    expected={}
    for (a,b),incident in neighbors.items():
        A,B=vertices[a],vertices[b]
        edge_length=distance(A,B); assert 0<=delta<edge_length
        assert 1<=len(incident)<=2
        if len(incident)==2:
            assert incident[0][1:]==incident[1][1:][::-1]
        mx,my=mid(A,B); vx,vy=vec(A,B)
        for side,key in ((-1,'minus'),(1,'plus')):
            k=f'contact/{a}+{b}/{key}'
            C=ports[k]
            assert set(C['faces'])=={face for face,_,_ in incident}
            assert C['role']==('interior' if len(incident)==2 else 'patch_boundary')
            assert distance(nodes[k],(mx-side*delta*vx/(2*edge_length),my-side*delta*vy/(2*edge_length)))<1e-9
            theta=p['contact_angle']+p['parquet_gradient']*mx
            assert abs(C['angle']-theta)<1e-10
            expected[k]=(A,B,theta)
    assert set(expected)==set(ports)
    for e in g['edges']:
        a,b=e['from'],e['to']
        degree[a]+=1;degree[b]+=1
        contact,bend=(a,b) if a in ports else (b,a)
        assert contact in ports and bend.startswith('bend/')
        assert e['face'] in ports[contact]['faces']
        edge_a,edge_b,theta=expected[contact]
        v=vec(nodes[contact],nodes[bend]);t=vec(edge_a,edge_b)
        assert math.hypot(*v)>0
        # Dot and cross provide an independent angle measurement.
        assert abs(math.degrees(math.atan2(abs(cross(v,t)),abs(dot(v,t))))-theta)<1e-7
        usage[contact].append((e['face'],v))
        bends[bend].append((e['face'],contact))
    for port,uses in usage.items():
        assert degree[port]==len(ports[port]['faces']) and len(uses) in (1,2)
        if len(uses)==2:
            assert uses[0][0]!=uses[1][0]
            v,w=uses[0][1],uses[1][1]
            if delta==0:
                assert abs(cross(v,w))<1e-8 and dot(v,w)<0
            else:
                a,b,_=expected[port];t=vec(a,b)
                assert dot(v,t)*dot(w,t)>0 and cross(v,t)*cross(w,t)<0
    for bend,uses in bends.items():
        assert degree[bend]==2 and uses[0][0]==uses[1][0] and uses[0][1]!=uses[1][1]
        face=faces[uses[0][0]]['vertices']; point=nodes[bend]
        for a,b in zip(face,face[1:]+face[:1]):
            assert cross(vec(vertices[a],vertices[b]),vec(vertices[a],point))>=-1e-9
    assert set(degree)==set(nodes)
    # Connected components may terminate only at real patch boundaries.
    links=defaultdict(set)
    for e in g['edges']:
        links[e['from']].add(e['to']);links[e['to']].add(e['from'])
    unseen=set(nodes); components=cycles=0
    while unseen:
        components+=1; stack=[unseen.pop()];ends=[]
        while stack:
            a=stack.pop()
            if degree[a]==1:ends.append(a)
            for b in links[a]&unseen:
                unseen.remove(b);stack.append(b)
        assert len(ends) in (0,2)
        assert all(ports[a]['role']=='patch_boundary' for a in ends)
        cycles+=not ends
    audit_greedy(p,faces,vertices,bends,nodes)
    if name in ('square','hexagonal'):
        audit_rotation(faces,vertices,bends,nodes)
    if name=='rosette':
        audit_rosette(p,faces,vertices)
    return {'faces':len(faces),'interior_contacts':sum(v==2 for v in degree.values())-len(bends),
            'bends':len(bends),'components':components,'closed_components':cycles}
def audit_greedy(settings,faces,vertices,bends,nodes):
    # Compare the selected path pairs against an independent analytic
    # candidate walk. Comparing indices avoids conflating coincident ports.
    used_in_face=defaultdict(set)
    for _,uses in bends.items():
        used_in_face[uses[0][0]].add(frozenset(u[1] for u in uses))
    delta=settings['displacement']
    for name,face in faces.items():
        ids=face['vertices']; poly=[vertices[x] for x in ids]
        lengths=[distance(a,b) for a,b in zip(poly,poly[1:]+poly[:1])]
        eps=max(lengths)*1e-10
        rays=[]
        for i,(a,b) in enumerate(zip(ids,ids[1:]+ids[:1])):
            A,B=vertices[a],vertices[b]
            dx,dy=vec(A,B); length=lengths[i]
            theta=math.radians(settings['contact_angle']+settings['parquet_gradient']*mid(A,B)[0])
            for side in (-1,1):
                key_side=side if delta==0 or a<b else -side
                lo,hi=sorted((a,b)); direction='plus' if key_side==1 else 'minus'
                key=f'contact/{lo}+{hi}/{direction}'
                tx,ty=dx/length,dy/length
                ray=(side*tx*math.cos(theta)-ty*math.sin(theta),side*ty*math.cos(theta)+tx*math.sin(theta))
                rays.append((i,key,nodes[key],ray))
        candidates=[]
        for i,(edge,_,a,u) in enumerate(rays):
            for j in range(i+1,len(rays)):
                other,_,b,v=rays[j]
                if edge==other:continue
                w=vec(a,b)
                if abs(cross(u,v))<=1e-12:
                    if abs(cross(w,u))<=eps and dot(u,v)<0 and dot(w,u)>eps:
                        candidates.append((math.floor(distance(a,b)/eps+.5),i,j))
                    continue
                # Solve the two forward distances by projection to line normals.
                t=cross(w,v)/cross(u,v); q=cross(w,u)/cross(u,v)
                if min(t,q)<=eps:continue
                meet=(a[0]+t*u[0],a[1]+t*u[1])
                if all(cross(vec(A,B),vec(A,meet))>=-eps*lengths[k]
                       for k,(A,B) in enumerate(zip(poly,poly[1:]+poly[:1]))):
                    candidates.append((math.floor((t+q)/eps+.5),i,j))
        matched=set();pairs=set()
        for _,i,j in sorted(candidates):
            if i in matched or j in matched:continue
            matched.update((i,j)); pairs.add(frozenset((rays[i][1],rays[j][1])))
        assert len(matched)==len(rays) and pairs==used_in_face[name],name

def audit_rotation(faces,vertices,bends,nodes):
    paths=defaultdict(list)
    for bend,uses in bends.items():
        paths[uses[0][0]].append((nodes[uses[0][1]],nodes[bend],nodes[uses[1][1]]))
    for name,f in faces.items():
        polygon=[vertices[i] for i in f['vertices']]
        n=len(polygon)
        cx,cy=(sum(p[i] for p in polygon)/n for i in range(2))
        cos,sin=math.cos(math.tau/n),math.sin(math.tau/n)
        def turn(p):
            x,y=p[0]-cx,p[1]-cy
            return (cx+cos*x-sin*y,cy+sin*x+cos*y)
        assert len(paths[name])==n
        for src in paths[name]:
            image=tuple(turn(p) for p in src)
            assert any(max(distance(a,b) for a,b in zip(image,candidate))<1e-8
                       or max(distance(a,b) for a,b in zip(image,candidate[::-1]))<1e-8
                       for candidate in paths[name]),name

def audit_rosette(pic,faces,vertices):
    r=pic['rosette']
    old=r['original_vertices']
    old_faces={f['id']:f['vertices'] for f in r['original_faces']}
    assert set(r['lineage'])==set(faces)
    inset={}
    for child,l in r['lineage'].items():
        if l['kind']!='regular-inset':continue
        parent=l['parent']
        v=[old[i] for i in old_faces[parent]]
        inner=[vertices[i] for i in faces[child]['vertices']]
        assert len(v)==len(inner)==8
        center=tuple(sum(p[k] for p in v)/8 for k in range(2))
        r0=distance(center,v[0]);r1=distance(center,inner[0])
        assert abs(r0-l['radius'])<1e-10 and abs(r1-l['inset_radius'])<1e-10
        assert abs(r1/r0-r['ratio']*(math.cos(math.pi/8)-math.sin(math.pi/8)*math.tan(3*math.pi/16)))<1e-10
        for i in range(8):
            edge_mid=mid(v[i],v[(i+1)%8])
            assert abs(cross(vec(center,edge_mid),vec(center,inner[i])))<1e-10
            if r['ratio']==1:
                assert abs(distance(inner[i],edge_mid)-distance(inner[i],inner[(i+1)%8])/2)<1e-10
        inset[parent]=inner
    for child,l in r['lineage'].items():
        if l['kind']!='bisector-fan':continue
        ring=faces[child]['vertices']; assert len(ring)==5
        central=l['vertex']; assert len(l['parents'])==3
        wedges=0
        for parent in l['parents']:
            ids=old_faces[parent]; i=ids.index(central)
            poly=[old[id_] for id_ in ids]
            current,following,previous=poly[i],poly[(i+1)%len(poly)],poly[i-1]
            if parent in inset:
                wedge=[current,mid(current,following),inset[parent][i],inset[parent][i-1],mid(previous,current)]
            else:
                assert len(poly)==4
                wedge=[current,mid(current,following),mid(poly[0],poly[2]),mid(previous,current)]
            wedges+=abs(area(wedge))
        assert abs(wedges-area([vertices[id_] for id_ in ring]))<1e-9,child

def audit_gap(g):
    polygon,angles,motif=g['polygon'],g['angles'],g['motif']
    rays=motif['rays']; used=set()
    for path in motif['paths']:
        total=0
        for key in ('first','second'):
            i=path[key]-1; assert i not in used; used.add(i)
            ray=rays[i]; edge=ray['edge']-1
            a,b=polygon[edge],polygon[(edge+1)%len(polygon)]
            assert distance(mid(a,b),ray['origin'])<1e-10
            t=vec(a,b);v=vec(ray['origin'],path['point'])
            assert abs(math.degrees(math.atan2(abs(cross(t,v)),abs(dot(t,v))))-angles[edge])<1e-8
            total+=math.hypot(*v)
        assert abs(total-path['cost'])<1e-9
    assert used==set(range(len(rays)))
    return len(used)

def raster(folder,existing):
    from PIL import Image,ImageChops,ImageStat
    result={}
    for name in (*NAMES,'border'):
        width,height=168,50 if name=='border' else 132
        a,b=[folder/f'{name}-{kind}.png' for kind in ('pdf','svg')]
        if not existing:
            subprocess.run(['pdftoppm','-r','152.4','-W',str(width),'-H',str(height),'-png','-singlefile',
                            str(folder/f'{name}.pdf'),str(a.with_suffix(''))],check=True)
            subprocess.run(['inkscape',str(folder/f'{name}.svg'),'--export-background=white',
                            '--export-background-opacity=1',f'--export-width={width}',f'--export-filename={b}'],check=True)
        ims=[Image.open(p).convert('RGB') for p in (a,b)]
        assert all(i.width==width and height<=i.height<=height+1 for i in ims),(name,[i.size for i in ims])
        ims=[i.crop((0,0,width,height)) for i in ims]
        ink=[sum(i.convert('L').histogram()[:210]) for i in ims]
        err=sum(ImageStat.Stat(ImageChops.difference(*ims)).mean)/(3*255)
        assert min(ink)>20 and err<.02,(name,ink,err)
        result[name]={'ink_pixels':ink,'mean_normalized_error':err}
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--existing-rasters',action='store_true')
    existing=parser.parse_args().existing_rasters
    checked=0
    for folder in sorted((ROOT/'build/islamic').glob('*')):
        receipts=sorted(folder.glob('receipt-Lua-*.json'))
        if not receipts:continue
        r=read(receipts[0])
        if not all(sha((ROOT/f['path']).read_bytes().replace(b'\r\n',b'\n'))==f['sha256'] for f in r['source']):continue
        assert r['source_digest']==folder.name
        for receipt in receipts[1:]:assert read(receipt)['outputs']==r['outputs']
        for f,h in r['outputs'].items():assert sha((folder/f).read_bytes())==h,f
        report={n:audit(read(folder/f'{n}.instance'),n) for n in NAMES}
        gap=audit_gap(read(folder/'gap.json'))
        results={'stage':'11','source_digest':folder.name,'fixtures':report,'gap_rays':gap,
                 'outputs':len(r['outputs']),'raster':raster(folder,existing)}
        (folder/'oracle.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf8')
        print('islamic_oracle: %d interior contacts, %d bend pairs, %d inferred gap rays' %
              (sum(x['interior_contacts'] for x in report.values()),sum(x['bends'] for x in report.values()),gap))
        checked+=1
    assert checked,'no current-source Islamic receipts'

if __name__=='__main__':
    main()

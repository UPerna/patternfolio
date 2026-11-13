"""Independent exact-arithmetic checker of source-bound Lua geometry reports."""
import collections
from decimal import Decimal as DecimalNumber, localcontext
from fractions import Fraction as F
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in ROOT.glob('*.lua')}
for name in ('tools/geometrycheck.lua', 'tools/geometry_oracle.py', 'docs/validation/fixtures/geometry-v1.json'):
    manifest[name] = hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
source_digest = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def cross(a, b): return a[0]*b[1]-a[1]*b[0]
def sub(a, b): return (a[0]-b[0], a[1]-b[1])
def exact_sign(points):
    a,b,c = [tuple(map(F,p)) for p in points]
    v = cross(sub(a,c),sub(b,c))
    return (v>0)-(v<0)

def segment(points):
    a,b,c,d = [tuple(map(F,p)) for p in points]
    if a==b or c==d: return 'degenerate',None
    ab,cd,ac = sub(b,a),sub(d,c),sub(c,a)
    det = cross(ab,cd)
    if det:
        t,u = cross(ac,cd)/det,cross(ac,ab)/det
        if 0<=t<=1 and 0<=u<=1: return 'point',(a[0]+t*ab[0],a[1]+t*ab[1])
        return 'none',None
    if cross(ac,ab): return 'none',None
    def on(p,q,r): return all(min(q[k],r[k])<=p[k]<=max(q[k],r[k]) for k in (0,1))
    common = {p for p in (a,b,c,d) if on(p,a,b) and on(p,c,d)}
    return ('none',None) if not common else ('point',next(iter(common))) if len(common)==1 else ('overlap',None)

def within_error(actual, expected, error):
    return sum((F(actual[k])-expected[k])**2 for k in (0,1)) <= F(error)**2

reports=0
totals=collections.Counter()
canonical_corpus=None
for path in sorted((ROOT/'build/geometry-oracle').glob('*.json')):
    envelope=json.loads(path.read_text(encoding='utf8'))
    payload=envelope['payload'].encode('utf8')
    digest=hashlib.sha256(payload).hexdigest()
    assert envelope['kind']=='cache_entry' and envelope['schema_version']==1
    assert envelope['key']==envelope['sha256']==path.stem==digest, 'Evidence envelope integrity failed'
    report=json.loads(payload)
    if report['source_digest']!=source_digest: continue
    reports+=1
    semantic_corpus={k:v for k,v in report.items() if k!='runtime'}
    if canonical_corpus is None:canonical_corpus=semantic_corpus
    else:assert semantic_corpus==canonical_corpus,'Current-source runtime corpora differ; investigate parity'
    for case in report['orientations']:
        assert case['sign']==exact_sign(case['points']), case
        totals['orientations']+=1
    for case in report['segments']:
        kind,point=segment(case['points'])
        assert case['result']['kind']==kind,case
        if point is not None:
            assert within_error(case['result']['point'],point,case['result']['error_bound']),case
        totals['segments']+=1
    curve_cases=[(case,collections.Counter(map(F,case['factored_roots']))) for case in report['curves']]
    curve_cases.extend((case,collections.Counter(F(n,d) for n,d in case['rational_roots'])) for case in report['general_curves'])
    for case,roots in curve_cases:
        controls=[[F(x),F(y)] for x,y in case['controls']]
        y=[p[1] for p in controls]
        actual=[y[0],3*(y[1]-y[0]),3*(y[0]-2*y[1]+y[2]),-y[0]+3*y[1]-3*y[2]+y[3]]
        degree=max(i for i,value in enumerate(actual) if value)
        expected=[actual[degree]]
        for root,multiplicity in roots.items():
            for _ in range(multiplicity):
                product=[F(0)]*(len(expected)+1)
                for i,value in enumerate(expected):product[i]-=root*value;product[i+1]+=value
                expected=product
        expected+= [F(0)]*(4-len(expected))
        assert actual==expected,'Known factored polynomial changed during fixture construction'
        events=case['result']['events']
        assert case['result']['status']=='complete' and len(events)==len(roots),case
        matched=set()
        for event in events:
            found=[root for root in roots if F(event['curve_interval'][0])<=root<=F(event['curve_interval'][1])]
            assert len(found)==1 and found[0] not in matched,case
            root=found[0];matched.add(root)
            assert event['multiplicity']==roots[root],case
            assert event['classification']==('tangent' if roots[root]%2==0 else 'crossing'),case
            weights=[(1-root)**3,3*root*(1-root)**2,3*root**2*(1-root),root**3]
            point=tuple(sum(weights[j]*controls[j][k] for j in range(4)) for k in (0,1))
            assert point[1]==0 and within_error(event['point'],point,event['error_bound']),case
        totals['cubics']+=1
    for case in report['bounds']:
        controls=[tuple(map(F,p)) for p in case['controls']];a,b,c,d,tx,ty=map(F,case['matrix'])
        world=[(a*x+c*y+tx,b*x+d*y+ty) for x,y in controls]
        geometry=case['result']['geometry'];ink=case['result']['bounds']
        # Independent 70-digit power-basis derivative roots, plus exact rational samples.
        with localcontext() as context:
            context.prec=70
            dec=lambda q:DecimalNumber(q.numerator)/DecimalNumber(q.denominator)
            for axis in (0,1):
                p,q,r,s=(dec(v[axis]) for v in world)
                coeff=(-p+3*q-3*r+s,3*p-6*q+3*r,-3*p+3*q,p)
                qa,qb,qc=3*coeff[0],2*coeff[1],coeff[2]
                times=[DecimalNumber(0),DecimalNumber(1)]
                if qa:
                    disc=qb*qb-4*qa*qc
                    if disc>=0:
                        times.extend([(-qb-disc.sqrt())/(2*qa),(-qb+disc.sqrt())/(2*qa)])
                elif qb:times.append(-qc/qb)
                for t in times:
                    if 0<=t<=1:
                        value=((coeff[0]*t+coeff[1])*t+coeff[2])*t+coeff[3]
                        assert dec(F(geometry[axis]))<=value<=dec(F(geometry[axis+2])),case
        radius=F(case['stroke_width'])/2
        for j in range(33):
            t=F(j,32);w=((1-t)**3,3*t*(1-t)**2,3*t*t*(1-t),t**3)
            point=tuple(sum(w[k]*world[k][axis] for k in range(4)) for axis in (0,1))
            for dx,dy in ((radius,0),(-radius,0),(0,radius),(0,-radius)):
                offset=(a*dx+c*dy,b*dx+d*dy)
                assert all(F(ink[k])<=point[k]+offset[k]<=F(ink[k+2]) for k in (0,1)),case
        totals['bounds']+=1
assert reports>0,'No immutable oracle report matches current source bytes; run texlua tools/geometrycheck.lua'
print('geometry_oracle: Fraction checks passed;',dict(totals),'across',reports,'current-source reports')

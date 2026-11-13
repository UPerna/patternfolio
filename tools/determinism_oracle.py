import pathlib,json,hashlib,re
dest=pathlib.Path(__file__).resolve().parents[1]/'docs/validation/fixtures/determinism-v1.json'
cases=[('empty',b''),('abc',b'abc')]+[(f'padding-{n}',b'x'*n) for n in (55,56,63,64,65)]+[('all-byte-values',bytes(range(256))),('million-a',b'a'*1000000)]
vectors={'schema_version':1,'profile':'pattern-canonical-v1 / sha256-frame-v1 / pm16807-schrage-v1','sha256':[],'numbers':[],'streams':[],'sorted_object':'{"a":2,"z":1,"α":3}'}
for name,data in cases:
 row={'name':name,'sha256':hashlib.sha256(data).hexdigest()}
 if name=='all-byte-values':row['hex']=data.hex()
 elif name=='million-a':row.update(repeat_text='a',count=1000000)
 else:row['text']=data.decode()
 vectors['sha256'].append(row)
for source in ['0','-0.0','1','-17','0.1','1e-7','1e-20','1e20','9007199254740991','2.2250738585072014e-308','1.7976931348623157e308']:
 val=float(source);s='0' if val==0 else format(val,'.17g');s=re.sub(r'e([+-]?)0*(\d+)',lambda m:'e'+('-' if m[1]=='-' else '+')+m[2],s)
 vectors['numbers'].append({'input':source,'canonical':s})
for namespace,name,identity in [('fixture/flower@1','flowers','plant/root/flower/0'),('fixture/flower@1','visitors','bee/0'),('fixture/flower@1','flowers','plant/root/flower/1')]:
 obj={'seed':7,'namespace':namespace,'name':name,'semantic_id':identity};payload=json.dumps(obj,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode();domain=b'random/pm16807-schrage-v1';frame=lambda b:str(len(b)).encode()+b':'+b
 digest=hashlib.sha256(b'pattern-platform\0hash-v1\0'+frame(domain)+frame(payload)).hexdigest();seed=int(digest[:8],16)%2147483646+1;state=seed;first=[]
 for _ in range(5):state=16807*state%2147483647;first.append(state)
 vectors['streams'].append(dict(root=7,namespace=namespace,name=name,semantic_id=identity,seed=seed,first=first))
assert json.loads(dest.read_text(encoding='utf8'))==vectors, 'Golden vector mismatch; investigate without regenerating baselines'
print('determinism_oracle: independent Python hashlib, canonical-number and modular-integer vectors passed')

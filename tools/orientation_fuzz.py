import pathlib,sys,os,math,random,json,collections,hashlib
from fractions import Fraction as F
import argparse
parser=argparse.ArgumentParser(description='Optional Lupa/Fraction orientation fuzz; never rewrites fixtures')
parser.add_argument('--lua-module-dir',type=pathlib.Path)
parser.add_argument('--receipt',type=pathlib.Path)
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
if args.lua_module_dir:sys.path.insert(0,str(args.lua_module_dir.resolve()))
from lupa.lua53 import LuaRuntime
os.chdir(root);lua=LuaRuntime(unpack_returned_tuples=True);orient=lua.eval('require("pattern_predicates").orient2d')
randomizer=random.Random(504031);methods=collections.Counter();bad_naive=[];cases=[]
def exact(p):
 a,b,c=[[F(v) for v in point] for point in p];d=(a[0]-c[0])*(b[1]-c[1])-(a[1]-c[1])*(b[0]-c[0]);return (d>0)-(d<0)
for i in range(10000):
 scale=10.0**randomizer.randint(-40,40)
 if i%2:
  a=[randomizer.uniform(-3,3)*scale for _ in range(2)];b=[randomizer.uniform(-3,3)*scale for _ in range(2)];t=randomizer.random();c=[a[k]+t*(b[k]-a[k]) for k in range(2)]
  if i%3:c[1]=math.nextafter(c[1],math.inf if i%3==1 else -math.inf)
  p=[a,b,c]
 else:p=[[randomizer.uniform(-3,3)*scale for _ in range(2)] for _ in range(3)]
 expected=exact(p);actual,evidence=orient(*(lua.table_from(x) for x in p));assert actual==expected,(p,expected,actual)
 methods[evidence['method']]+=1
 a,b,c=p;d=(a[0]-c[0])*(b[1]-c[1])-(a[1]-c[1])*(b[0]-c[0]);naive=(d>0)-(d<0)
 if naive!=expected and len(bad_naive)<8:bad_naive.append({'points':p,'sign':expected,'naive_sign':naive})
 if len(cases)<12 and i<12:cases.append({'points':p,'sign':expected})

receipt={'seed':504031,'cases':10000,'oracle':'Python Fraction.from_float exact rational determinant','status':'passed','methods':dict(methods),'naive_failures_preserved':bad_naive,'numeric_admission':'coordinates zero or abs in 1e-50..1e50; generated scales 1e-40..1e40'}
receipt['source_lf_sha256']=hashlib.sha256(pathlib.Path('pattern_predicates.lua').read_bytes().replace(b'\r\n',b'\n')).hexdigest()
receipt['runtime']=lua.eval('_VERSION')
if args.receipt:
 args.receipt.parent.mkdir(parents=True,exist_ok=True)
 args.receipt.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf8')
print('10000 exact Fraction orientation comparisons passed',dict(methods),'naive counterexamples',len(bad_naive))

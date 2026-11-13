"""Serial bounded workload measurements, resumable by exact source/input bytes."""
import argparse,hashlib,json,os,platform,re,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def source(root):
 files={p.name:sha(p)for p in root.glob('*.lua')}
 for name in('tools/perf_run.lua','tools/perf_workloads.lua','tools/perf_prepare.lua'):files[name]=sha(root/name)
 return files
def main():
 p=argparse.ArgumentParser();p.add_argument('--lua',default='texlua');p.add_argument('--lua-arg',action='append',default=[]);p.add_argument('--label',default='measure');p.add_argument('--timeout',type=float,default=300);p.add_argument('--case',action='append');p.add_argument('--resume',action='store_true');p.add_argument('--compare-root',type=Path);a=p.parse_args()
 assert re.fullmatch(r'[A-Za-z0-9_-]+',a.label)and 1<=a.timeout<=600
 manifest=read(ROOT/'build/performance/workloads.json');assert manifest['status']=='passed'and len(manifest['cases'])==27
 rows=[r for r in manifest['cases']if not a.case or r['id']in a.case];assert rows
 out=ROOT/'build/performance';summary=out/('summary-'+a.label+'.json');results=[]
 roots=[('baseline',a.compare_root.resolve())]if a.compare_root else []
 roots.append(('candidate',ROOT));sources={name:source(root)for name,root in roots}
 hardware={'platform':platform.platform(),'machine':platform.machine(),'python':platform.python_version(),'logical_cpus':os.cpu_count(),'reported_cpu':platform.processor(),'power_thermal_background_activity':'uncontrolled','whole_process_memory_limit':'not claimed'}
 if Path('/proc/cpuinfo').is_file():hardware['reported_cpu']=next((line.split(':',1)[1].strip()for line in Path('/proc/cpuinfo').read_text().splitlines()if line.startswith('model name')),hardware['reported_cpu'])
 if hasattr(os,'sysconf'):hardware['os_visible_ram_bytes']=os.sysconf('SC_PHYS_PAGES')*os.sysconf('SC_PAGE_SIZE')
 def save(status):summary.write_text(json.dumps({'status':status,'label':a.label,'hardware_runtime':hardware,'scope':'Serial actual shared Lua core; each fresh process measures generation/warm generation/validated replay plus real PDF/SVG serialization. No concurrent benchmark children.','timeout_seconds_per_workload':a.timeout,'source_files':sources,'results':results},indent=2)+'\n',encoding='utf8')
 save('in_progress')
 for row in rows:
  entry={'id':row['id'],'class':row['class'],'size':row['size'],'measurements':{}}
  for name,root in roots:
   assert sha(root/'build/performance'/row['recipe_path'])==row['recipe_sha256']
   label=a.label+'-'+name;folder=root/'build/performance/results';folder.mkdir(parents=True,exist_ok=True)
   existing=list(folder.glob(row['id']+'-'+label+'-Lua-*.json'))
   reusable=[p for p in existing if read(p).get('status')=='passed'and read(p).get('source_files_sha256')==sources[name]and read(p).get('workload')==row]
   if a.resume and len(reusable)==1:
    result=read(reusable[0]);entry['measurements'][name]={'status':'passed','receipt':str(reusable[0]),'receipt_sha256':sha(reusable[0]),'resumed':True,'data':result};continue
   if existing:
    for old in existing:
     target=old.with_name(old.name+'.previous-'+sha(old)[:12]);assert not target.exists();old.rename(target)
   command=[a.lua,*a.lua_arg,'tools/perf_run.lua',row['id'],label];started=time.perf_counter()
   try:
    run=subprocess.run(command,cwd=root,capture_output=True,timeout=a.timeout)
    elapsed=time.perf_counter()-started
    stdout=out/(row['id']+'-'+label+'.stdout.log');stderr=out/(row['id']+'-'+label+'.stderr.log');stdout.write_bytes(run.stdout);stderr.write_bytes(run.stderr)
    paths=list(folder.glob(row['id']+'-'+label+'-Lua-*.json'))
    data=read(paths[0])if len(paths)==1 and paths[0].stat().st_size else None
    valid=run.returncode==0 and data is not None and data['status']=='passed'and data['source_files_sha256']==sources[name]and data['workload']==row
    entry['measurements'][name]={'status':'passed'if valid else 'failed','returncode':run.returncode,'whole_child_wall_seconds':elapsed,'stdout_sha256':sha(stdout),'stderr_sha256':sha(stderr),'receipt':str(paths[0])if len(paths)==1 else None,'receipt_sha256':sha(paths[0])if len(paths)==1 else None,'data':data,'error_tail':run.stderr.decode('utf8',errors='replace')[-1600:]if not valid else None}
   except subprocess.TimeoutExpired as error:
    entry['measurements'][name]={'status':'bounded_timeout','whole_child_wall_seconds':time.perf_counter()-started,'accepted_complete_result':False,'diagnostic':'Owned benchmark child killed after explicit wall budget; no passing result claimed','stdout_tail':(error.stdout or b'').decode('utf8',errors='replace')[-1000:]}
  if len(roots)==2 and all(x['status']=='passed'for x in entry['measurements'].values()):
   before=entry['measurements']['baseline']['data'];after=entry['measurements']['candidate']['data'];pairs=[]
   for b,c in zip(before['phases'],after['phases']):
    assert b['phase']==c['phase']and b['instance_sha256']==c['instance_sha256']and b['scene_sha256']==c['scene_sha256'],('Before/after semantic drift',row['id'],b['phase'])
    pairs.append({'phase':b['phase'],'baseline_seconds':b['total_seconds'],'candidate_seconds':c['total_seconds'],'baseline_over_candidate':b['total_seconds']/c['total_seconds'],'instance_sha256':c['instance_sha256'],'scene_sha256':c['scene_sha256']})
   entry['paired_semantic_hashes_equal']=True;entry['comparisons']=pairs
  results.append(entry);save('in_progress');print('Measured serial workload',row['id'],{k:v['status']for k,v in entry['measurements'].items()},flush=True)
 status='passed'if all(v['status']=='passed'for r in results for v in r['measurements'].values())else 'failed';save(status)
 assert status=='passed','Actual workload failures remain visible in '+str(summary)
if __name__=='__main__':main()

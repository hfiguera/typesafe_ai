import argparse
from collections import defaultdict,Counter
import hashlib,json
from pathlib import Path
from statistics import median
import sys
sys.path.insert(0,str(Path('bench').resolve()))
from summarize_mixed import summarize,passes

parser=argparse.ArgumentParser();parser.add_argument('root',type=Path);args=parser.parse_args()
p=args.root;m=json.loads((p/'main.json').read_text());corpus=json.loads(Path('bench/fixtures/system_one/manifest.json').read_text())
assert m['complete'] and len(m['cases'])==108
expected={(rep,client,workload) for rep in range(1,4) for client in m['clients'] for workload in m['workloads']}
actual=set();totals=Counter();groups=defaultdict(list);fingerprints=set();byid={c['id']:c for c in corpus['cases']}
for c in m['cases']:
 r=json.loads((p/c['file']).read_text());key=(c['repetition'],c['variant'],c['workload']);assert key not in actual;actual.add(key)
 assert r['offered_requests']==5000 and r['offered_rps']==1000 and r['connections']==4 and r['protocol']=='http2' and r['target']=='offline' and r['delay']==5
 assert sum(r['outcomes'].values())+r['driver_dropped']==5000
 assert sum(b['offered_requests'] for b in r['timeline'])==5000
 assert sum(b['driver_dropped'] for b in r['timeline'])==r['driver_dropped']
 timeline=Counter()
 for b in r['timeline']:timeline.update(b['outcomes'])
 assert dict(timeline)==r['outcomes']
 if c['workload']!='synthetic_noul':
  f=byid[c['workload']]
  assert r['recording_id']==c['workload'] and r['response_sha256']==f['response_sha256'] and r['request_sha256']==f['request_sha256']
  assert r['request_body_bytes']==f['request_bytes'] and r['response_body_bytes']==f['response_bytes'] and r['questions']==f['questions']
  assert r['usage_source']=='recorded_response_replayed_not_live_usage'
  assert 'recording' not in r
 fingerprints.add((r['source_sha256'],r['environment']['harness_sha256'],r['environment']['lock_sha256']))
 totals.update(r['outcomes']);totals['driver_dropped']+=r['driver_dropped'];totals['offered']+=5000
 groups[(c['workload'],c['variant'])].append(r)
assert actual==expected and len(fingerprints)==1 and totals['offered']==540000
smoke=json.loads((p/'smoke.json').read_text());assert len(smoke['results'])==64 and all(r['outcome']=='ok' for r in smoke['results'])
assert len({(r['recording_id'],r['protocol'],r['client']) for r in smoke['results']})==64
body=summarize([p/'main.json']).replace('# Mixed-load investigation: complete comparison tables','# Recorded-response replay: complete comparison tables',1)
Path('bench/REPLAY-DATA.md').write_text(body)
validation={'cases':108,'offered_requests':540000,'totals':dict(totals),'smoke_checks':64,'protocols_checked':['http1','http2'],'timed_protocol':'http2','fingerprints':dict(zip(['source_sha256','harness_sha256','lock_sha256'],next(iter(fingerprints)))),'checks':['exact planned case set, three repetitions per client/workload','recorded request/response hashes and byte counts match corpus','common workload/rate/connection/protocol settings','offered = outcomes + driver drops','per-second accounting','consistent source/harness/dependency fingerprints','both HTTP protocols preserve expected responses for all four clients'],'live_usage':'Offline timing reports repeat captured token metadata; they are not additional live usage.'}
(p/'validation.json').write_text(json.dumps(validation,indent=2)+'\n')
print(json.dumps(validation,indent=2))
print('| Case | TypeSafe p99 / passes | Finch | Req | ReqLLM |')
for case in m['workloads']:
 cells=[]
 for client in m['clients']:
  rs=groups[(case,client)];p99=[r['success_latency_from_scheduled_arrival_ms']['p99'] for r in rs]
  cells.append(f'{min(p99):.2f}–{max(p99):.2f} ms; {sum(map(passes,rs))}/3')
 print('| '+case+' | '+' | '.join(cells)+' |')
print('CPU medians /1000 successful')
for case in m['workloads']:
 print(case,{c:round(median(r['vm_cpu_ms']*1000/r['outcomes']['ok'] for r in groups[(case,c)]),2) for c in m['clients']})

from collections import Counter
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path('bench').resolve()))
from mixed_comparison import schedule
from summarize_network import analyze
root=Path(sys.argv[1])
manifest,groups,deltas=analyze(root/'paired.json')
expected=schedule(['typesafe','finch','req','req_llm'],[3000,6000,8000,10000],['mixed'],3,20260917,True)
actual=[];total=Counter();sample_counts=[]
for case in manifest['cases']:
 row=json.loads((root/case['file']).read_text())
 actual.append((case['repetition'],case['variant'],row['offered_rps'],case['workload'],case['network']))
 assert row['offered_requests']==row['offered_rps']*15
 assert row['source_sha256']=='136ecd3ba154175eb62d0104325da5f882b530e4dbf5134a3afc06e4e14fd97e'
 assert row['environment']['harness_sha256']=='429f7771d8c5a90470327e7f74dbded8b850fefb908689d8eb4f129f65c90b52'
 assert row['environment']['elixir']=='1.20.4' and row['environment']['schedulers']==4
 assert row['target']=='offline' and row['protocol']=='http2'
 assert row['connections']==4 and row['sample_storage']=='ets'
 assert row['large_every']==10 and row['bytes']==65536 and row['questions']==1 and row['delay']==5
 assert len(row['timeline'])==15
 assert sum(b['offered_requests'] for b in row['timeline'])==row['offered_requests']
 assert sum(b['driver_dropped'] for b in row['timeline'])==row['driver_dropped']
 timeline=Counter();workloads=Counter()
 for bucket in row['timeline']:timeline.update(bucket['outcomes'])
 for cls in row['workloads'].values():workloads.update(cls['outcomes'])
 assert dict(timeline)==row['outcomes']==dict(workloads)
 total.update(row['outcomes']);total['driver_dropped']+=row['driver_dropped'];total['offered']+=row['offered_requests']
 sample_counts.append(len(case['host_samples']))
assert actual==expected and len(actual)==96
assert total['offered']==9720000
assert all(len(rows)==3 for rows in groups.values())
assert len(deltas)==48
smoke=json.loads((root/'smoke.json').read_text());assert smoke['complete'] and len(smoke['cases'])==8
for case in smoke['cases']:
 row=json.loads((root/case['file']).read_text());assert row['outcomes']=={'ok':100} and row['driver_dropped']==0
result={'validated_cases':96,'validated_pairs':48,'smoke_successful_requests':800,'totals':dict(total),'case_host_samples_min_max':[min(sample_counts),max(sample_counts)],'checks':['exact planned schedule and pair order','matching library/harness/lock fingerprints','expected runtime, workload, connection and sample-storage settings','offered = all outcomes + dropped','per-second and payload-class outcome accounting','all three repetitions present','800 verified-TLS smoke successes'],'production_changes':False}
(root/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))

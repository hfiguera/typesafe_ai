#!/usr/bin/env python3
"""Run a declared offline experiment plan, retaining all cases and runtime flags.

Run from bench/: python3 tail_experiments.py PLAN.json OUTPUT_PREFIX
The plan contains repetitions, seed and variants (name, flags, script, args).
"""
import json
import os
from pathlib import Path
import random
import resource
import subprocess
import sys
import time


def run(plan_path, prefix):
    plan = json.loads(plan_path.read_text())
    manifest_path = prefix.with_suffix('.json')
    if manifest_path.exists():
        raise ValueError('Use a fresh output prefix')
    prefix.parent.mkdir(parents=True, exist_ok=True)
    schedule = []
    rng = random.Random(plan['seed'])
    for rep in range(1, plan['repetitions'] + 1):
        block = [(rep, v) for v in plan['variants']]
        rng.shuffle(block)
        schedule.extend(block)
    manifest = {'complete': False, 'plan': plan, 'cases': [],
                'note': 'Offline only; process CPU includes startup and aggregation, VM CPU is the timed interval. No API key passed.'}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    for rep, variant in schedule:
        output = Path(f"{prefix}-{variant['name']}-{rep}.json")
        if output.exists():
            raise ValueError(f'Existing case: {output}')
        command = ['mix', 'run', variant.get('script', 'load.exs'), *variant['args'], '--output', str(output)]
        assert '--live' not in command
        env = os.environ.copy()
        env.pop('TYPESAFE_API_KEY', None)
        env['ERL_FLAGS'] = variant['flags']
        start = time.time()
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        with output.with_suffix('.log').open('w') as log:
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        row = json.loads(output.read_text())
        case = {'variant': variant['name'], 'repetition': rep, 'file': output.name,
                'command': command, 'erl_flags': env['ERL_FLAGS'], 'started_at': start,
                'finished_at': time.time(), 'process_cpu_seconds':
                    after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                'network_environment': {k: env[k] for k in ['BENCH_PORT', 'ERL_INETRC', 'BENCH_FIXTURE_DESCRIPTION'] if k in env}}
        manifest['cases'].append(case)
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        print(f"{len(manifest['cases'])}/{len(schedule)} {variant['name']}: p99={row['success_latency_from_scheduled_arrival_ms']['p99']} lag={row['driver_launch_lag_ms']['p99']} CPU={row['vm_cpu_ms']}ms outcomes={row['outcomes']} drops={row['driver_dropped']}", flush=True)
    manifest['complete'] = True
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    run(Path(sys.argv[1]), Path(sys.argv[2]))

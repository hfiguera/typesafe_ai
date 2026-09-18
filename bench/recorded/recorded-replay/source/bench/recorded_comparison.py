#!/usr/bin/env python3
"""Offline recorded-response screen; run from bench/ with a separate fixture."""
import argparse
import json
import os
from pathlib import Path
import random
import subprocess
import time
from mixed_comparison import host_sample


def run(args):
    corpus = json.loads((args.recordings / 'manifest.json').read_text())
    assert corpus['complete']
    workloads = ['synthetic_noul'] + [c['id'] for c in corpus['cases']]
    clients = args.clients.split(',')
    assert all(c in ['typesafe', 'finch', 'req', 'req_llm'] for c in clients)
    assert args.rate > 0 and args.seconds > 0 and args.repetitions > 0 and args.delay >= 0
    rng = random.Random(args.seed)
    scenarios = []
    for rep in range(1, args.repetitions + 1):
        block = [(rep, c, w) for c in clients for w in workloads]
        rng.shuffle(block)
        scenarios.extend(block)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    manifest_path = args.output.with_suffix('.json')
    if manifest_path.exists():
        raise ValueError('Use a new output prefix; existing runs are never overwritten')
    manifest = {'complete': False, 'kind': 'offline_recorded_response_screen',
                'seed': args.seed, 'seconds': args.seconds, 'repetitions': args.repetitions,
                'rate': args.rate, 'delay_ms': args.delay, 'protocol': 'http2',
                'connections': 4, 'clients': clients, 'workloads': workloads,
                'planned_cases': len(scenarios), 'cases': [],
                'note': 'Fresh BEAM per case; synthetic inputs with captured response bodies. Fixed fixture sleep, not replayed inference latency. Token metadata is replayed, not live usage. CPU includes client VM and driver; this common-load screen does not establish capacity.'}
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    for index, (rep, client, workload) in enumerate(scenarios, 1):
        output = Path(f'{args.output}-{client}-{workload}-{rep}.json')
        command = ['mix', 'run', 'load.exs', '--client', client, '--rate', str(args.rate),
                   '--requests', str(args.rate * args.seconds), '--connections', '4',
                   '--max-concurrency', '128', '--max-queue', '1024', '--delay', str(args.delay),
                   '--output', str(output)]
        if workload != 'synthetic_noul':
            command += ['--recording', workload, '--recordings-dir', str(args.recordings)]
        env = os.environ.copy()
        env.pop('TYPESAFE_API_KEY', None)
        env.setdefault('ERL_FLAGS', '+S 4:4')
        start = time.time()
        samples = [host_sample()]
        with output.with_suffix('.log').open('w') as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            while True:
                try:
                    code = process.wait(timeout=2)
                    samples.append(host_sample())
                    if code:
                        raise subprocess.CalledProcessError(code, command)
                    break
                except subprocess.TimeoutExpired:
                    samples.append(host_sample())
        row = json.loads(output.read_text())
        manifest['cases'].append({'variant': client, 'workload': workload, 'repetition': rep,
                                  'file': output.name, 'command': command, 'started_at': start,
                                  'finished_at': time.time(), 'host_samples': samples,
                                  'erl_flags': env['ERL_FLAGS'], 'network_environment': {
                                      key: env[key] for key in ['BENCH_PORT', 'ERL_INETRC', 'BENCH_FIXTURE_DESCRIPTION'] if key in env}})
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
        print(f"{index}/{len(scenarios)} {client} {workload}: p99={row['success_latency_from_scheduled_arrival_ms']['p99']}ms drops={row['driver_dropped']} outcomes={row['outcomes']}", flush=True)
    manifest['complete'] = True
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recordings', type=Path, default=Path('fixtures/system_one'))
    parser.add_argument('--clients', default='typesafe,finch,req,req_llm')
    parser.add_argument('--rate', type=int, default=1000)
    parser.add_argument('--seconds', type=int, default=5)
    parser.add_argument('--repetitions', type=int, default=3)
    parser.add_argument('--seed', type=int, default=20260917)
    parser.add_argument('--delay', type=int, default=5)
    parser.add_argument('--output', type=Path, required=True)
    run(parser.parse_args())

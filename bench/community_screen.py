#!/usr/bin/env python3
"""Offline fresh-VM screen with Linux thermal admission checks and full accounting."""
import argparse
import json
import os
from pathlib import Path
import random
import subprocess
import time


def host():
    temperatures = {str(p): int(p.read_text()) for p in Path('/sys/class/thermal').glob('thermal_zone*/temp')}
    counters = {str(p): int(p.read_text()) for p in Path('/sys/devices/system/cpu').glob('cpu*/thermal_throttle/*throttle_count')}
    if not temperatures or not counters:
        raise RuntimeError('Linux temperature and throttle observations are required')
    return {'unix_seconds': time.time(), 'temperatures': temperatures, 'throttle_counts': counters}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plan', type=Path)
    parser.add_argument('prefix', type=Path)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    manifest_path = args.prefix.with_suffix('.json')
    if manifest_path.exists():
        raise ValueError('Use a fresh output prefix')
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {'complete': False, 'plan': plan, 'cases': [], 'cooling': [], 'interrupted': None}
    save = lambda: manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    rng = random.Random(plan['seed'])
    schedule = []
    for repetition in range(1, plan['repetitions'] + 1):
        block = [(repetition, v) for v in plan['variants']]
        rng.shuffle(block)
        schedule.extend(block)
    try:
        for repetition, variant in schedule:
            ready = 0
            deadline = time.monotonic() + 180
            while ready < 3:
                observation = host()
                manifest['cooling'].append(observation)
                ready = ready + 1 if max(observation['temperatures'].values()) <= 70000 else 0
                if time.monotonic() > deadline:
                    raise RuntimeError('Host did not cool below 70 C; stop instead of claiming capacity')
                time.sleep(2)
            before = host()
            output = Path(f'{args.prefix}-{variant["name"]}-{repetition}.json')
            command = ['mix', 'run', 'load.exs', *variant['args'], '--output', str(output)]
            assert '--live' not in command
            env = os.environ.copy()
            env.pop('TYPESAFE_API_KEY', None)
            env['ERL_FLAGS'] = variant['flags']
            case = {'variant': variant['name'], 'repetition': repetition, 'file': output.name,
                    'command': command, 'erl_flags': variant['flags'], 'started_at': time.time(),
                    'before': before, 'samples': [], 'finished_at': None}
            with output.with_suffix('.log').open('w') as log:
                process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
                try:
                    while process.poll() is None:
                        case['samples'].append(host())
                        time.sleep(.5)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=10)
            case['finished_at'] = time.time()
            case['after'] = host()
            case['exit_code'] = process.returncode
            case['thermal_clean'] = all(case['after']['throttle_counts'][k] == v for k,v in before['throttle_counts'].items())
            case['peak_temperature_c'] = max(v for sample in case['samples'] for v in sample['temperatures'].values()) / 1000
            manifest['cases'].append(case)
            save()
            if process.returncode != 0:
                raise RuntimeError('Benchmark case failed; see retained log')
            row = json.loads(output.read_text())
            print(f'{len(manifest["cases"])}/{len(schedule)} {variant["name"]} #{repetition}: p99={row["success_latency_from_scheduled_arrival_ms"]["p99"]} lag={row["driver_launch_lag_ms"]["p99"]} clean={case["thermal_clean"]} peak={case["peak_temperature_c"]}', flush=True)
            if not case['thermal_clean']:
                raise RuntimeError('Thermal throttling recurred; retained case is not capacity evidence')
        manifest['complete'] = True
    except BaseException as error:
        manifest['interrupted'] = type(error).__name__ + ': ' + str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    main()

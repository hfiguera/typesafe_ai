#!/usr/bin/env python3
"""Verify archived community evidence hashes, accounting, host gates, and fingerprints."""
import argparse
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path, default=Path('recorded/community'))
    args = parser.parse_args()
    root = args.directory
    manifest = read(root / 'manifest.json')
    for name, digest in manifest['sha256'].items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
    phases = manifest['completed_timing_phases']
    totals = {'measured': 0, 'warmup': 0, 'cases': 0, 'errors': 0, 'drops': 0, 'latency_passes': 0}
    for phase in phases:
        m = read(root / phase)
        assert m['complete']
        assert len(m['cases']) == len(m['plan']['variants']) * m['plan']['repetitions']
        assert {(c['variant'], c['repetition']) for c in m['cases']} == {(v['name'], rep) for v in m['plan']['variants'] for rep in range(1, m['plan']['repetitions'] + 1)}
        fingerprints = set()
        for c in m['cases']:
            assert c['thermal_clean'] and c['exit_code'] == 0
            assert all(c['after']['throttle_counts'][k] == v for k, v in c['before']['throttle_counts'].items())
            r = read(root / c['file'])
            assert sum(r['outcomes'].values()) + r['driver_dropped'] == r['offered_requests']
            good = (r['outcomes'].get('ok', 0) == r['offered_requests'] and r['driver_dropped'] == 0 and r['success_latency_from_scheduled_arrival_ms']['p99'] <= 20 and r['driver_launch_lag_ms']['p99'] <= 5 and r['within_budget_fraction_of_offered'] >= .99)
            totals['latency_passes'] += int(good)
            fingerprints.add((r['source_sha256'], r['environment']['harness_sha256'], r['environment']['lock_sha256']))
            totals['measured'] += r['offered_requests']
            totals['warmup'] += r['warmup_requests']
            totals['cases'] += 1
            totals['errors'] += sum(v for k, v in r['outcomes'].items() if k != 'ok')
            totals['drops'] += r['driver_dropped']
        assert len(fingerprints) == 1
        archive = root / (manifest['initial_harness'] if phase == 'community-controlled.json' else manifest['defaults_harness'])
        files = [archive / 'mix.exs', archive / 'mix.lock', *archive.glob('lib/**/*.ex'), *archive.glob('config/*.exs')]
        digest = hashlib.sha256()
        for f in sorted(files, key=lambda f: f.relative_to(archive).as_posix()):
            digest.update(f.relative_to(archive).as_posix().encode() + b'\0' + f.read_bytes())
        assert digest.hexdigest() == next(iter(fingerprints))[1]
    for row in read(root / 'host-summary.json'):
        assert row['mac_thermal_states'] == [0]
        assert row['linux_package_throttle_delta'] == 0
        assert all(value == 0 for value in row['network_errors_and_drops_delta'].values())
    native = read(root / 'native-sdk-probe.json')
    assert len(native['rows']) == 8
    assert all(r['outcome'] == 'ok' and r['protocol'] == 'HTTP/1.1' for r in native['rows'])
    behavior = read(root / 'behavior.json')
    assert len(behavior['cases']) == 28
    assert all(c['fixture_requests'] == 1 for c in behavior['cases'])
    rejected = read(root / 'community-screen.json')
    assert not rejected['complete'], 'Interrupted screen must remain visibly incomplete'
    print(json.dumps({'hashes_verified': len(manifest['sha256']), 'controlled': totals,
                      'behavior_probes': 28, 'interrupted_screen_cases': len(rejected['cases'])}, indent=2))


if __name__ == '__main__':
    main()

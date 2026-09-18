#!/usr/bin/env python3
"""Validate archived tail experiments and regenerate their complete tables.

Run from the repository root with the evidence directory as the only argument.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
from summarize_tail import summarize

PHASES = ['mac-timer', 'linux-timer', 'screen', 'runtime', 'profile', 'candidate',
          'wakeup', 'work', 'rate', 'inline', 'confirm']


def validate(root):
    evidence_path = root / 'manifest.json'
    evidence = json.loads(evidence_path.read_text()) if evidence_path.exists() else None
    corpus_dir = Path('bench/fixtures/system_one')
    corpus = json.loads((corpus_dir / 'manifest.json').read_text())
    corpus = {c['id']: c for c in corpus['cases']}
    for entry in corpus.values():
        for part in ['request', 'response']:
            body = (corpus_dir / entry[f'{part}_file']).read_bytes()
            assert len(body) == entry[f'{part}_bytes']
            assert hashlib.sha256(body).hexdigest() == entry[f'{part}_sha256']
    totals = Counter()
    phases = {}
    fingerprints = set()
    for phase in PHASES:
        manifest = json.loads((root / f'{phase}.json').read_text())
        assert manifest['complete']
        plan = manifest['plan']
        expected = {(rep, v['name']) for rep in range(1, plan['repetitions'] + 1) for v in plan['variants']}
        actual = set()
        phase_totals = Counter()
        for case in manifest['cases']:
            key = (case['repetition'], case['variant'])
            assert key not in actual
            actual.add(key)
            variant = next(v for v in plan['variants'] if v['name'] == case['variant'])
            row = json.loads((root / case['file']).read_text())
            args = variant['args']
            def arg(name):
                return args[args.index(name) + 1]
            assert row['offered_requests'] == int(arg('--requests'))
            assert row['offered_rps'] == int(arg('--rate'))
            assert case['erl_flags'] == variant['flags']
            if evidence:
                library = variant.get('environment', {}).get('TYPESAFE_BENCH_PATH', '')
                version = Path(library).name.removeprefix('typesafe-tail-') if library else 'baseline'
                assert row['environment']['source_sha256'] == evidence['versions'][version]['source_sha256']
            outcomes = Counter(row['outcomes'])
            assert sum(outcomes.values()) + row['driver_dropped'] == row['offered_requests']
            timeline = Counter()
            for bucket in row['timeline']:
                timeline.update(bucket['outcomes'])
            assert timeline == outcomes
            assert sum(b['offered_requests'] for b in row['timeline']) == row['offered_requests']
            assert sum(b['driver_dropped'] for b in row['timeline']) == row['driver_dropped']
            phase_totals['cases'] += 1
            phase_totals['offered'] += row['offered_requests']
            phase_totals['ok'] += outcomes['ok']
            phase_totals['errors'] += sum(outcomes.values()) - outcomes['ok']
            phase_totals['drops'] += row['driver_dropped']
            fingerprints.add((row['environment']['source_sha256'], row['environment']['harness_sha256'], row['environment']['lock_sha256']))
            if '--recording' in args:
                entry = corpus[arg('--recording')]
                assert row['recording_id'] == entry['id']
                assert row['client'] == arg('--client')
                assert row['connections'] == int(arg('--connections'))
                assert row['target'] == 'offline' and row['protocol'] == 'http2'
                assert row['delay'] == 5
                assert row['request_sha256'] == entry['request_sha256']
                assert row['response_sha256'] == entry['response_sha256']
                assert row['usage_source'] == 'recorded_response_replayed_not_live_usage'
                phase_totals['http_offered'] += row['offered_requests']
                phase_totals['http_warmup'] += row['warmup_requests']
            else:
                assert row['kind'] == 'timer_only_control'
                phase_totals['timer_control_offered'] += row['offered_requests']
        assert actual == expected
        phases[phase] = dict(phase_totals)
        totals.update(phase_totals)
    validation = {'totals': dict(totals), 'phases': phases,
                  'fingerprints': [dict(zip(['source_sha256', 'harness_sha256', 'lock_sha256'], f)) for f in sorted(fingerprints)],
                  'checks': ['exact planned variant/repetition sets', 'flags, clients, rates, request and connection counts',
                             'offline recorded-body identity and checksums', 'per-second and total outcome/drop accounting'],
                  'note': 'Instrumented profile is included in HTTP accounting, not a performance claim. All token metadata is replayed; no live API requests.'}
    (root / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    Path('bench/TAIL-LATENCY-DATA.md').write_text(summarize([root / f'{p}.json' for p in PHASES]).rstrip() + '\n')
    print(json.dumps(validation, indent=2))


if __name__ == '__main__':
    validate(Path(sys.argv[1]))

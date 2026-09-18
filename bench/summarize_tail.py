#!/usr/bin/env python3
"""Summarize all declared variants, including failures; run from bench/."""
import collections
import json
from pathlib import Path
import statistics
import sys
from summarize_mixed import passes


def spread(values):
    return f'{statistics.median(values):.3f} [{min(values):.3f}–{max(values):.3f}]'


def summarize(paths):
    lines = ['# Tail-latency investigation: complete tables', '',
             'Cells show median [min–max] of run statistics, not pooled percentiles.',
             'CPU includes the client VM and arrival driver. Process CPU also includes startup, warmup and aggregation.',
             'Pass requires zero errors/drops, ≥1000 successes, scheduled p99 ≤20 ms, launch-lag p99 ≤5 ms, and ≥99% of offered calls within 20 ms.',
             'Timer controls and instrumented profiles are diagnostics, not client performance claims.', '']
    for path in paths:
        manifest = json.loads(path.read_text())
        assert manifest['complete']
        groups = collections.defaultdict(list)
        for case in manifest['cases']:
            row = json.loads((path.parent / case['file']).read_text())
            assert sum(row['outcomes'].values()) + row['driver_dropped'] == row['offered_requests']
            groups[case['variant']].append((case, row))
        lines += [f'## {path.stem}', '',
                  '| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |',
                  '|---|---:|---:|---:|---:|---:|---:|']
        for variant in manifest['plan']['variants']:
            pairs = groups[variant['name']]
            assert len(pairs) == manifest['plan']['repetitions']
            rows = [r for _, r in pairs]
            good = lambda r: r['outcomes'].get('ok', 0)
            errors = sum(sum(r['outcomes'].values()) - good(r) for r in rows)
            drops = sum(r['driver_dropped'] for r in rows)
            result = (f'{sum(passes(r) for r in rows)}/{len(rows)}'
                      if 'within_budget_fraction_of_offered' in rows[0] else 'n/a')
            cells = [variant['name'], spread([r['success_latency_from_scheduled_arrival_ms']['p99'] for r in rows]),
                     spread([r['driver_launch_lag_ms']['p99'] for r in rows]),
                     spread([r['vm_cpu_ms'] * 1000 / good(r) for r in rows]),
                     spread([c['process_cpu_seconds'] for c, _ in pairs]), f'{errors} / {drops}', result]
            lines.append('| ' + ' | '.join(cells) + ' |')
        lines += ['', 'Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.', '']
    return '\n'.join(lines)


if __name__ == '__main__':
    print(summarize([Path(p) for p in sys.argv[1:]]))

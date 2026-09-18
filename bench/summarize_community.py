#!/usr/bin/env python3
"""Summarize the offline community screen; preserve every repetition and failure."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
from statistics import median


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', default='community-controlled.json')
    args = parser.parse_args()
    root = args.directory
    manifest = read(root / args.manifest)
    assert manifest['complete']
    assert len(manifest['cases']) == len(manifest['plan']['variants']) * manifest['plan']['repetitions']
    grouped = defaultdict(list)
    total = warmup = 0
    fingerprints = set()
    for case in manifest['cases']:
        row = read(root / case['file'])
        assert row['offered_requests'] == sum(row['outcomes'].values()) + row['driver_dropped']
        total += row['offered_requests']
        warmup += row['warmup_requests']
        fingerprints.add((row['source_sha256'], row['environment']['harness_sha256'], row['environment']['lock_sha256']))
        grouped[(row['profile'], row['recording_id'], row['offered_rps'], row['client'])].append((case, row))
    assert all(c['thermal_clean'] and c['exit_code'] == 0 for c in manifest['cases'])
    assert len(fingerprints) == 1, 'Do not combine different harnesses or source versions'
    out = ['# Community SDK screen: complete tables', '',
           f'{len(manifest["cases"])} ten-second cases; {total:,} offered evaluations plus {warmup:,} warmups. Offline replay only.', '',
           'p99 is measured from scheduled arrival. CPU includes the client VM and driver. '
           'CPU is ms per 1000 successful requests. Rows summarize repetitions, not pooled requests. '
           'Passes require all offered requests to succeed, no driver drops, at least 1000 successes, '
           'p99 ≤20 ms, launch-lag p99 ≤5 ms, and ≥99% of arrivals completed within 20 ms. '
           'Host health is reported separately; this short screen does not establish maximum capacity.', '']
    for profile in ['matched', 'defaults']:
        if not any(key[0] == profile for key in grouped):
            continue
        out += [f'## {profile}', '', '| Shape / req/s | Client | p99 median (range), ms | Launch lag p99 range, ms | CPU median | Successful req/s median | Errors / drops | Passes |',
                '|---|---|---:|---:|---:|---:|---:|---:|']
        for (p, shape, rate, client), entries in sorted(grouped.items()):
            if p != profile:
                continue
            rows = [r for _, r in entries]
            p99 = [r['success_latency_from_scheduled_arrival_ms']['p99'] for r in rows]
            lag = [r['driver_launch_lag_ms']['p99'] for r in rows]
            cpu = [r['vm_cpu_ms'] * 1000 / r['outcomes'].get('ok', 1) for r in rows]
            good = lambda r: (r['outcomes'].get('ok', 0) == r['offered_requests'] and r['driver_dropped'] == 0 and r['outcomes'].get('ok', 0) >= 1000 and r['success_latency_from_scheduled_arrival_ms']['p99'] <= 20 and r['driver_launch_lag_ms']['p99'] <= 5 and r['within_budget_fraction_of_offered'] >= .99)
            errors = sum(sum(v for k,v in r['outcomes'].items() if k != 'ok') for r in rows)
            drops = sum(r['driver_dropped'] for r in rows)
            out.append(f'| {shape} / {rate} | {client} | {median(p99):.2f} ({min(p99):.2f}–{max(p99):.2f}) | {min(lag):.2f}–{max(lag):.2f} | {median(cpu):.1f} | {median(r["successful_rps_including_drain"] for r in rows):.1f} | {errors} / {drops} | {sum(good(r) for r in rows)}/{len(rows)} |')
        out += ['']
    out += ['## Every repetition', '', '| Case | p50 / p95 / p99, ms | Lag p99, ms | CPU ms | Outcomes | Drops |', '|---|---:|---:|---:|---|---:|']
    for case in manifest['cases']:
        r = read(root / case['file'])
        latency = r['success_latency_from_scheduled_arrival_ms']
        out.append(f'| {case["variant"]} #{case["repetition"]} | {latency["p50"]:.2f} / {latency["p95"]:.2f} / {latency["p99"]:.2f} | {r["driver_launch_lag_ms"]["p99"]:.2f} | {r["vm_cpu_ms"]} | {r["outcomes"]} | {r["driver_dropped"]} |')
    args.output.write_text('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()

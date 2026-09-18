#!/usr/bin/env python3
"""Validate and summarize an adjacent-pair direct/SSH network experiment."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
from statistics import mean, median

from summarize_mixed import passes, spread, summarize


def analyze(path):
    manifest = json.loads(path.read_text())
    if not manifest["complete"] or not manifest["paired_network"]:
        raise ValueError("Expected a complete paired-network manifest")
    if len({c["workload"] for c in manifest["cases"]}) != 1:
        raise ValueError("Summarize one workload per network experiment; do not pool unlike workloads")
    pairs = defaultdict(dict)
    groups = defaultdict(list)
    fingerprints = set()
    for position, case in enumerate(manifest["cases"]):
        row = json.loads((path.parent / case["file"]).read_text())
        key = (case["variant"], case["workload"], row["offered_rps"], case["repetition"])
        network = case["network"]
        if network not in ["direct", "ssh"] or network in pairs[key]:
            raise ValueError(f"Invalid or duplicate path in {key}")
        if sum(row["outcomes"].values()) + row["driver_dropped"] != row["offered_requests"]:
            raise ValueError(f"Outcome mismatch in {case['file']}")
        fingerprints.add((row["source_sha256"], row["environment"]["harness_sha256"],
                          row["environment"]["lock_sha256"]))
        pairs[key][network] = (position, case, row)
        groups[(case["variant"], row["offered_rps"], network)].append(row)
    if len(fingerprints) != 1:
        raise ValueError("Library, harness, or dependencies differ between cases")
    deltas = []
    for (client, workload, rate, rep), pair in pairs.items():
        if set(pair) != {"direct", "ssh"}:
            raise ValueError("Incomplete network pair")
        di, dc, direct = pair["direct"]
        si, sc, ssh = pair["ssh"]
        if abs(di - si) != 1:
            raise ValueError("Network pair is not adjacent")
        for key in ["offered_requests", "connections", "bytes", "questions", "large_every",
                    "max_in_flight", "max_concurrency", "max_queue", "timeout_ms",
                    "sample_storage", "budget_ms", "delay", "warmup_requests", "target", "protocol"]:
            if direct[key] != ssh[key]:
                raise ValueError(f"Pair configuration mismatch: {key}")
        deltas.append({"client": client, "workload": workload, "rate": rate, "repetition": rep,
                       "first": "direct" if di < si else "ssh",
                       "p99_direct_minus_ssh_ms": direct["success_latency_from_scheduled_arrival_ms"]["p99"] - ssh["success_latency_from_scheduled_arrival_ms"]["p99"],
                       "rps_direct_minus_ssh": direct["successful_rps_including_drain"] - ssh["successful_rps_including_drain"],
                       "drops_direct_minus_ssh": direct["driver_dropped"] - ssh["driver_dropped"],
                       "direct_pass": passes(direct), "ssh_pass": passes(ssh)})
    return manifest, groups, deltas


def render(path, output):
    manifest, groups, deltas = analyze(path)
    derived = []
    for network in ["direct", "ssh"]:
        dest = path.with_name(f"{path.stem}-{network}.json")
        dest.write_text(json.dumps({**manifest, "derived_from": path.name,
                                   "cases": [c for c in manifest["cases"] if c["network"] == network]}, indent=2) + "\n")
        derived.append(dest)
    lines = [summarize(derived), "## Adjacent-pair differences", "",
             "Each difference is direct minus SSH for the same client, rate and repetition.",
             "Negative p99 means direct was lower; positive req/s means direct completed more per second.",
             "These are full repetition ranges, not confidence intervals or pooled percentiles.", "",
             "| Client | Offered req/s | p99 difference ms | Successful req/s difference | Drop difference | Lower p99 on direct |",
             "|---|---:|---:|---:|---:|---:|"]
    for client, rate in sorted(set((d["client"], d["rate"]) for d in deltas)):
        rows = [d for d in deltas if d["client"] == client and d["rate"] == rate]
        values = [spread([d[k] for d in rows]) for k in
                  ["p99_direct_minus_ssh_ms", "rps_direct_minus_ssh", "drops_direct_minus_ssh"]]
        lines.append(f"| {client} | {rate} | " + " | ".join(values)
                     + f" | {sum(d['p99_direct_minus_ssh_ms'] < 0 for d in rows)}/{len(rows)} |")
    output.write_text("\n".join(lines) + "\n")
    path.with_name(f"{path.stem}-differences.json").write_text(json.dumps(deltas, indent=2) + "\n")


def hosts(path):
    """Client case timestamps use the Linux clock; align Mac samples approximately."""
    manifest = json.loads(path.read_text())
    root = path.parent
    linux = [json.loads(s) for s in (root / "linux-monitor.jsonl").read_text().splitlines()]
    mac = [json.loads(s) for s in (root / "mac-monitor.jsonl").read_text().splitlines()]
    offset = json.loads((root / "clock-start.json").read_text())["remote_minus_local_midpoint_seconds"]

    def describe(samples, linux_host):
        if len(samples) < 2:
            raise ValueError("Insufficient host samples")
        cpu, rx, tx = [], [], []
        for a, b in zip(samples, samples[1:]):
            if linux_host:
                aa = [int(n) for n in a["host_cpu_ticks"].split()[1:9]]
                bb = [int(n) for n in b["host_cpu_ticks"].split()[1:9]]
                total = sum(bb) - sum(aa)
                idle = bb[3] + bb[4] - aa[3] - aa[4]
                seconds = b["unix_seconds"] - a["unix_seconds"]
                for values, key in [(rx, "rx_bytes"), (tx, "tx_bytes")]:
                    values.append((b["network"][key] - a["network"][key]) * 8 / seconds / 1e6)
            else:
                aa, bb = a["cpu_ticks"], b["cpu_ticks"]
                total = sum(bb.values()) - sum(aa.values())
                idle = bb["idle"] - aa["idle"]
            if total > 0:
                cpu.append(100 * (total - idle) / total)
        result = {"samples": len(samples), "host_cpu_mean_percent": mean(cpu),
                  "host_cpu_max_interval_percent": max(cpu)}
        if linux_host:
            temp = "/sys/class/thermal/thermal_zone1/temp"
            throttle = "/sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count"
            result.update(package_temp_celsius_range=[min(s["sysfs"][temp] for s in samples) / 1000,
                                                     max(s["sysfs"][temp] for s in samples) / 1000],
                          package_throttle_delta=samples[-1]["sysfs"][throttle] - samples[0]["sysfs"][throttle],
                          rx_max_interval_mbps=max(rx), tx_max_interval_mbps=max(tx),
                          network_error_drop_deltas={key: samples[-1]["network"][key] - samples[0]["network"][key]
                                                    for key in ["rx_errors", "tx_errors", "rx_dropped", "tx_dropped"]})
        else:
            result["thermal_states"] = sorted(set(s["thermal_state"] for s in samples))
        return result

    def window(start, end):
        return {"linux_client": describe([s for s in linux if start <= s["unix_seconds"] <= end], True),
                "mac_server": describe([s for s in mac if start - offset <= s["unix_seconds"] <= end - offset], False)}

    result = {"scope": "Whole-host observations at 2 s intervals, including case startup/warmup/aggregation. Linux case clock; Mac aligned using initial offset. Overall window padded by 2 s. No per-process SSH CPU attribution.",
              "remote_minus_local_midpoint_seconds": offset,
              "overall": window(manifest["cases"][0]["started_at"] - 2,
                                manifest["cases"][-1]["finished_at"] + 2),
              "cases": [{"file": c["file"], "client": c["variant"], "network": c["network"],
                         **window(c["started_at"], c["finished_at"])} for c in manifest["cases"]]}
    (root / "host-summary.json").write_text(json.dumps(result, indent=2) + "\n")


def plot(path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    _, groups, _ = analyze(path)
    fig, axes = plt.subplots(2, 2, figsize=(11, 8), sharex=True, sharey=True)
    for ax, (client, label) in zip(axes.flat, [("typesafe", "TypeSafe"), ("finch", "Finch"),
                                            ("req", "Req"), ("req_llm", "ReqLLM")]):
        rates = sorted({rate for c, rate, _ in groups if c == client})
        for network, color in [("direct", "#007e80"), ("ssh", "#bc6c25")]:
            buckets = [groups[(client, rate, network)] for rate in rates]
            values = [[r["success_latency_from_scheduled_arrival_ms"]["p99"] for r in rows]
                      for rows in buckets]
            medians = [median(v) for v in values]
            ax.plot(rates, medians, label="Direct HTTPS" if network == "direct" else "HTTPS through SSH",
                    color=color)
            ax.fill_between(rates, [min(v) for v in values], [max(v) for v in values], color=color, alpha=0.12)
            for rate, value, rows in zip(rates, medians, buckets):
                ax.scatter(rate, value, color=color, marker="o" if all(passes(r) for r in rows) else "x", s=45)
        ax.axhline(20, color="#555555", linestyle="--", linewidth=1, label="20 ms p99 budget")
        ax.set(title=label, yscale="log", xticks=rates)
        ax.grid(alpha=0.15)
    axes[0, 0].legend(fontsize=9)
    fig.suptitle("Linux clients → Mac fixture · same wired link", fontsize=14)
    fig.supxlabel("Offered requests / second", y=0.10)
    fig.supylabel("Scheduled-arrival p99 (ms)")
    fig.text(0.5, 0.025, "Median and full range of three 15-second repetitions; lines connect tested points only.\n"
             "Circle: all repetitions pass every check. Cross: at least one fails.\n"
             "Successful-only percentiles: read with drops/errors. Synthetic fixture; Linux thermal limits apply.",
             ha="center", fontsize=9)
    fig.tight_layout(rect=(0.025, 0.12, 1, 0.96))
    fig.savefig(path.with_suffix(".png"), dpi=140)
    fig.savefig(path.with_suffix(".svg"))
    svg = path.with_suffix(".svg")
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--hosts", action="store_true", help="Join adjacent monitor and clock-start files")
    parser.add_argument("--plot", action="store_true", help="Requires optional matplotlib dependency")
    args = parser.parse_args()
    render(args.manifest, args.output)
    if args.hosts:
        hosts(args.manifest)
    if args.plot:
        plot(args.manifest)

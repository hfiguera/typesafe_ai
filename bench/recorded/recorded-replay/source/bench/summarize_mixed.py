#!/usr/bin/env python3
"""Summarize every repetition from mixed_comparison.py manifests (stdlib only)."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
from statistics import median


def passes(row):
    return (row["outcomes"] == {"ok": row["offered_requests"]}
            and row["driver_dropped"] == 0
            and row["offered_requests"] >= 1000
            and row["success_latency_from_scheduled_arrival_ms"]["p99"] <= 20
            and row["driver_launch_lag_ms"]["p99"] <= 5
            and row["within_budget_fraction_of_offered"] >= 0.99)


def spread(values):
    return f"{median(values):.2f} [{min(values):.2f}–{max(values):.2f}]"


def summarize(paths):
    lines = ["# Mixed-load investigation: complete comparison tables", "",
             "Cells are median [min–max] across run statistics, not pooled percentiles.",
             "Pass: every offered call succeeds, no drops, ≥1000 samples, scheduled-arrival",
             "p99 ≤20 ms, launch-lag p99 ≤5 ms, and ≥99% of offered calls within 20 ms.",
             "CPU and reductions include the client VM and driver; memory is a snapshot.", ""]
    for path in paths:
        manifest = json.loads(path.read_text())
        if not manifest["complete"]:
            raise ValueError(f"Incomplete manifest: {path}")
        lines.extend([f"## {path.stem}", ""])
        groups = defaultdict(list)
        for case in manifest["cases"]:
            row = json.loads((path.parent / case["file"]).read_text())
            key = (case["workload"], row["connections"], row["offered_rps"], case["variant"])
            groups[key].append(row)
        lines.extend(["| Workload / connections / offered req/s | Client | Scheduled p50 ms | p95 ms | p99 ms | Successful req/s | Errors / drops | Passes |",
                      "|---|---|---:|---:|---:|---:|---:|---:|"])
        for (workload, connections, rate, client), rows in sorted(groups.items()):
            latencies = [spread([r["success_latency_from_scheduled_arrival_ms"][p] for r in rows])
                         for p in ["p50", "p95", "p99"]]
            rps = spread([r["successful_rps_including_drain"] for r in rows])
            errors = sum(sum(n for k, n in r["outcomes"].items() if k != "ok") for r in rows)
            drops = sum(r["driver_dropped"] for r in rows)
            lines.append(f"| {workload} / {connections} / {rate} | {client} | "
                         + " | ".join(latencies)
                         + f" | {rps} | {errors} / {drops} | {sum(map(passes, rows))}/{len(rows)} |")
        lines.extend(["", "| Workload / connections / offered req/s | Client | API p99 ms | Launch-lag p99 ms | CPU ms / 1000 successful | Reductions / successful | Driver heap bytes at end |",
                      "|---|---|---:|---:|---:|---:|---:|"])
        for (workload, connections, rate, client), rows in sorted(groups.items()):
            metrics = [spread([r["success_latency_ms"]["p99"] for r in rows]),
                       spread([r["driver_launch_lag_ms"]["p99"] for r in rows]),
                       spread([r["vm_cpu_ms"] * 1000 / r["outcomes"]["ok"] for r in rows]),
                       spread([r["vm_reductions"] / r["outcomes"]["ok"] for r in rows]),
                       spread([r["driver_memory_bytes_at_end"] for r in rows])]
            lines.append(f"| {workload} / {connections} / {rate} | {client} | " + " | ".join(metrics) + " |")
        lines.append("")
    return "\n".join(lines)


def plot(path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    manifest = json.loads(path.read_text())
    if not manifest["complete"]:
        raise ValueError(f"Incomplete manifest: {path}")
    groups = defaultdict(list)
    for case in manifest["cases"]:
        row = json.loads((path.parent / case["file"]).read_text())
        groups[(case["workload"], row["connections"], case["variant"])].append(row)
    panels = sorted(set((workload, count) for workload, count, _ in groups))
    fig, axes = plt.subplots(1, len(panels), figsize=(9 * len(panels), 5), squeeze=False)
    styles = [("baseline", "Previous TypeSafe", "#667085"),
              ("typesafe", "Current TypeSafe", "#007e80"),
              ("finch", "Finch", "#bc6c25"), ("req", "Req", "#7753ad"),
              ("req_llm", "ReqLLM", "#c93d60")]
    for ax, (workload, count) in zip(axes[0], panels):
        one_rate = len({r["offered_rps"] for (w, c, _), rs in groups.items()
                        if (w, c) == (workload, count) for r in rs}) == 1
        tick_positions, tick_labels = [], []
        for position, (variant, label, color) in enumerate(styles):
            rows = groups[(workload, count, variant)]
            if not rows:
                continue
            rates = sorted(set(r["offered_rps"] for r in rows))
            buckets = [[r for r in rows if r["offered_rps"] == rate] for rate in rates]
            values = [[r["success_latency_from_scheduled_arrival_ms"]["p99"] for r in rs]
                      for rs in buckets]
            medians = [median(v) for v in values]
            coordinates = [position] if one_rate else rates
            tick_positions.append(position)
            tick_labels.append(label)
            ax.plot(coordinates, medians, label=label, color=color, linewidth=1.5)
            ax.fill_between(coordinates, [min(v) for v in values], [max(v) for v in values],
                            color=color, alpha=0.10)
            if len(rates) == 1:
                ax.errorbar(coordinates, medians,
                            yerr=[[medians[0] - min(values[0])], [max(values[0]) - medians[0]]],
                            fmt="none", ecolor=color, capsize=3, alpha=0.6)
            for rate, runs, value in zip(coordinates, buckets, medians):
                ax.scatter([rate], [value], color=color, s=45,
                           marker="o" if all(passes(r) for r in runs) else "x")
        ax.axhline(20, color="#555555", linestyle="--", linewidth=1)
        ax.set(title=f"{workload} · {count} connections", xlabel="Offered requests / second",
               ylabel="Scheduled-arrival p99 (ms)", yscale="log")
        ax.grid(alpha=0.15)
        if one_rate:
            ax.set_xticks(tick_positions, tick_labels)
            ax.set_xlabel(f"Client · {rates[0]:,} offered requests / second")
        else:
            ax.legend(fontsize=9)
    fig.suptitle(path.stem + " · median and full repetition range", fontsize=13)
    fig.text(0.5, 0.02, "Circle: every repetition passes all checks. Cross: at least one fails.\n"
             "Ranges: min–max, not confidence intervals. Synthetic fixture; see report for host conditions.",
             ha="center", fontsize=9)
    fig.tight_layout(rect=(0, 0.09, 1, 0.95))
    fig.savefig(path.with_suffix(".png"), dpi=140)
    fig.savefig(path.with_suffix(".svg"))
    svg = path.with_suffix(".svg")
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--plot", action="store_true")
    args = parser.parse_args()
    args.output.write_text(summarize(args.manifests))
    if args.plot:
        for manifest in args.manifests:
            plot(manifest)

#!/usr/bin/env python3
"""Rebuild auditable summary tables; optional plots require matplotlib.

Usage: python3 summarize_curves.py recorded/mac-curves.json recorded/linux-curves.json
       python3 summarize_curves.py --plot recorded/mac-curves.json
"""
import argparse
import collections
import json
import pathlib
import statistics

CLIENTS = ("typesafe", "finch", "req", "req_llm")
LABELS = ("TypeSafe", "Finch", "Req", "ReqLLM")


def groups(rows, *keys):
    result = collections.defaultdict(list)
    for row in rows:
        result[tuple(row[k] for k in keys)].append(row)
    return result


def percentile_values(rows, family="success_latency_from_scheduled_arrival_ms", percentile="p99"):
    return [r[family][percentile] for r in rows if r[family][percentile] is not None]


def errors(rows):
    return sum(sum(n for k, n in r["outcomes"].items() if k != "ok") for r in rows)


def summary(path, data):
    assert data["complete"] and len(data["results"]) == data["planned_scenarios"]
    rows = data["results"]
    for row in rows:
        assert sum(row["outcomes"].values()) + row["driver_dropped"] == row["offered_requests"]
        assert row["source_sha256"] == data["environment"]["source_sha256"]
    if data["kind"] == "offline_latency_curves":
        config = data["config"]
        actual = collections.Counter((r["client"], r["connections"], r["workload"], r["offered_rps"], r["repetition"]) for r in rows)
        expected = collections.Counter((client, connections, workload, rate, repetition)
            for client in config["clients"] for connections in config["connections"]
            for workload in config["workloads"] for rate in config["rates"]
            for repetition in range(1, config["repetitions"] + 1))
        assert actual == expected, "Missing or duplicated scenario repetitions"
    print(f"## {path.stem}\n")
    offered = sum(r["offered_requests"] for r in rows)
    drops = sum(r["driver_dropped"] for r in rows)
    print(f"{len(rows)} scenarios; {offered:,} offered; {errors(rows):,} client/driver errors; {drops:,} driver drops.\n")
    if data["kind"] == "live_jev_sanity":
        print("Small live sample: median of each run's p50 and full observed p99 range. The latter is nearly a maximum for eight calls; **not a tail-latency estimate**.\n")
        print("| Client | Offered req/s | Measured calls | Run p50 median (ms) | Observed run p99 range (ms) |")
        print("|---|---:|---:|---:|---:|")
        for (client, rate), runs in sorted(groups(rows, "client", "offered_rps").items()):
            p50 = percentile_values(runs, "success_latency_ms", "p50")
            p99 = percentile_values(runs, "success_latency_ms")
            print(f"| {client} | {rate} | {sum(r['offered_requests'] for r in runs)} | {statistics.median(p50):.2f} | {min(p99):.2f}–{max(p99):.2f} |")
        usage = {k: sum(r["observed_usage_including_warmup"][k] for r in rows) for k in ["input_tokens", "output_tokens"]}
        print(f"\nObserved usage, including warmup: {usage}. Models: {sorted(set(m for r in rows for m in r['models']))}.\n")
        return
    print("Highest tested offered rate with a contiguous passing prefix, **every repetition passing**. This is a finite local experiment, not sustained production capacity. `—` means no qualifying prefix.\n")
    print("| Workload | Connections | " + " | ".join(LABELS) + " |")
    print("|---|---:|" + "---:|" * 4)
    capacities = groups(data["capacity"], "workload", "connections")
    for (workload, connections), entries in sorted(capacities.items()):
        cells = []
        by_client = {e["client"]: e for e in entries}
        for client in CLIENTS:
            entry = by_client.get(client)
            rate = entry and entry["highest_tested_passing_offered_rps"]
            cells.append(str(rate) if rate is not None else "—")
        print(f"| {workload} | {connections} | " + " | ".join(cells) + " |")
    print("\nScheduled-arrival p99 in ms: **median [min–max] across runs**, followed by passing repetitions / total. These are distributions of run percentiles, not a pooled percentile.\n")
    print("| Workload | Connections | Offered req/s | " + " | ".join(LABELS) + " |")
    print("|---|---:|---:|" + "---|" * 4)
    for (workload, connections, rate), entries in sorted(groups(rows, "workload", "connections", "offered_rps").items()):
        by_client = groups(entries, "client")
        cells = []
        for client in CLIENTS:
            runs = by_client.get((client,), [])
            values = percentile_values(runs)
            passes = sum(r["budget_check"]["passes"] for r in runs)
            if values:
                cells.append(f"{statistics.median(values):.2f} [{min(values):.2f}–{max(values):.2f}]; {passes}/{len(runs)}")
            else:
                cells.append("—")
        print(f"| {workload} | {connections} | {rate} | " + " | ".join(cells) + " |")
    print("\nFailures and resource diagnostics across all rates. CPU covers the whole client VM, including the generator. Memory is end-of-run snapshots, not peaks.\n")
    print("| Client | Successful calls | Errors | Driver drops | VM CPU ms / 1,000 successes | Largest end snapshot (MiB) |")
    print("|---|---:|---:|---:|---:|---:|")
    for client in CLIENTS:
        runs = [r for r in rows if r["client"] == client]
        if not runs:
            continue
        ok = sum(r["outcomes"].get("ok", 0) for r in runs)
        cpu = sum(r["vm_cpu_ms"] for r in runs) * 1000 / max(1, ok)
        memory = max(r["vm_memory_after_bytes"] for r in runs) / 1024**2
        print(f"| {client} | {ok:,} | {errors(runs):,} | {sum(r['driver_dropped'] for r in runs):,} | {cpu:.1f} | {memory:.1f} |")
    print()


def plot(path, data):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    workloads = sorted(set(r["workload"] for r in data["results"]))
    connections = sorted(set(r["connections"] for r in data["results"]))
    fig, axes = plt.subplots(len(workloads), len(connections), figsize=(12, 3.3 * len(workloads)), squeeze=False)
    colors = ("#007e80", "#bc6c25", "#7753ad", "#c93d60")
    for i, workload in enumerate(workloads):
        for j, count in enumerate(connections):
            ax = axes[i, j]
            rows = [r for r in data["results"] if r["workload"] == workload and r["connections"] == count]
            for client, label, color in zip(CLIENTS, LABELS, colors):
                buckets = sorted(groups([r for r in rows if r["client"] == client], "offered_rps").items())
                points = [(key[0], percentile_values(runs), all(r["budget_check"]["passes"] for r in runs)) for key, runs in buckets]
                points = [p for p in points if p[1]]
                x = [p[0] for p in points]
                y = [statistics.median(p[1]) for p in points]
                ax.plot(x, y, color=color, label=label, linewidth=1.7)
                ax.fill_between(x, [min(p[1]) for p in points], [max(p[1]) for p in points], color=color, alpha=0.10)
                for rate, values, passes in points:
                    ax.scatter([rate], [statistics.median(values)], color=color, marker="o" if passes else "x", s=25)
            ax.axhline(data["config"]["budget_ms"], color="#555", linestyle="--", linewidth=1)
            ax.set_title(f"{workload} · {count} connection(s)")
            ax.set_yscale("log")
            ax.set_xlabel("Offered requests / second")
            ax.set_ylabel("Scheduled-arrival p99 (ms)")
            ax.grid(alpha=0.18)
    axes[0, 0].legend(loc="upper left", fontsize=8)
    fig.suptitle(path.stem + " · median and min–max across repetitions", fontsize=15)
    fig.text(0.5, 0.01, "○ all repetitions pass budget/error/driver checks   × at least one fails   Dashed: chosen local latency budget\nSuccessful-request latency only; inspect errors and driver drops in the report. Local fixture, not Jev capacity.", ha="center", fontsize=9)
    fig.tight_layout(rect=(0, 0.06, 1, 0.95))
    fig.savefig(path.with_suffix(".svg"))
    svg = path.with_suffix(".svg")
    svg.write_text("\n".join(line.rstrip(" \t") for line in svg.read_text().split("\n")))
    fig.savefig(path.with_suffix(".png"), dpi=110)
    plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plot", action="store_true")
    parser.add_argument("files", type=pathlib.Path, nargs="+")
    args = parser.parse_args()
    for source in args.files:
        document = json.loads(source.read_text())
        summary(source, document)
        if args.plot and document["kind"] == "offline_latency_curves":
            plot(source, document)

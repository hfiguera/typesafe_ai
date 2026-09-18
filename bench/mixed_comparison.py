#!/usr/bin/env python3
"""Paired, randomized mixed-load comparisons, using a fresh BEAM for each case.

Run from bench/ with a separate fixture already running. Each report and the
manifest record exact commands/settings. No live API or credentials are used.
"""
import argparse
import glob
import json
import os
from pathlib import Path
import random
import subprocess
import time

WORKLOADS = {"small": (256, 1, 0), "batch": (16384, 32, 0),
             "mixed": (65536, 1, 10), "medium_mix": (100000, 1, 10),
             "large_mix": (524288, 1, 10)}


def host_sample():
    """Linux observations only; missing sysfs files are simply unavailable."""
    patterns = ["/sys/devices/system/cpu/cpu*/thermal_throttle/*throttle_count",
                "/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq",
                "/sys/class/thermal/thermal_zone*/temp"]
    values = {}
    for pattern in patterns:
        for name in glob.glob(pattern):
            try:
                values[name] = int(Path(name).read_text())
            except (OSError, ValueError):
                pass
    return {"unix_seconds": time.time(), "sysfs": values}


def schedule(clients, rates, workloads, repetitions, seed, paired=False):
    """Keep network pairs adjacent, reversing each combination's order per block."""
    rng = random.Random(seed)
    combinations = [(client, rate, workload) for client in clients for rate in rates
                    for workload in workloads]
    first = list(range(len(combinations)))
    if paired:
        rng.shuffle(first)
    direct_first = {combinations[index]: rank % 2 == 0 for rank, index in enumerate(first)}
    cases = []
    for rep in range(1, repetitions + 1):
        block = combinations.copy()
        rng.shuffle(block)
        for client, rate, workload in block:
            paths = [None]
            if paired:
                paths = ["direct", "ssh"]
                if direct_first[(client, rate, workload)] != (rep % 2 == 1):
                    paths.reverse()
            cases.extend((rep, client, rate, workload, path) for path in paths)
    return cases


def run(args):
    assert args.repetitions > 0 and args.seconds > 0 and args.connections > 0
    rates = [int(n) for n in args.rates.split(",")]
    assert all(n > 0 for n in rates)
    clients = args.clients.split(",")
    assert all(c in ["baseline", "typesafe", "finch", "req", "req_llm"] for c in clients)
    workloads = args.workloads.split(",")
    assert all(w in WORKLOADS for w in workloads)
    if "baseline" in clients:
        assert args.baseline and (args.baseline / "mix.exs").is_file()
    paired = bool(args.network_pair)
    resolvers = dict(zip(["direct", "ssh"], args.network_pair or []))
    assert all(path.is_file() for path in resolvers.values())
    cases = schedule(clients, rates, workloads, args.repetitions, args.seed, paired)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"complete": False, "seed": args.seed, "seconds": args.seconds,
                "repetitions": args.repetitions, "cases": [],
                "paired_network": paired,
                "note": "Fresh client BEAM per case; fixture remains running. Network pairs are adjacent and reverse order per repetition; baseline changes library path only."}
    manifest_path = args.output.with_suffix(".json")
    for index, (rep, client, rate, workload, network) in enumerate(cases, 1):
        state_bytes, questions, large_every = WORKLOADS[workload]
        suffix = f"-{network}" if network else ""
        output = Path(f"{args.output}-{client}-{workload}-{rate}-{rep}{suffix}.json")
        env = os.environ.copy()
        env.setdefault("ERL_FLAGS", "+S 4:4")
        if network:
            env["ERL_INETRC"] = str(resolvers[network].resolve())
            env["BENCH_FIXTURE_DESCRIPTION"] = f"Mac fixture / Linux client over wired Ethernet; {network} path"
        env["TYPESAFE_BENCH_PATH"] = str(args.baseline.resolve() if client == "baseline" else Path("..").resolve())
        command = ["mix", "run", "load.exs", "--client", "typesafe" if client == "baseline" else client,
                   "--rate", str(rate), "--requests", str(rate * args.seconds),
                   "--connections", str(args.connections), "--max-concurrency", "128", "--max-queue", "1024",
                   "--large-every", str(large_every), "--bytes", str(state_bytes),
                   "--questions", str(questions), "--sample-storage", args.storage,
                   "--output", str(output)]
        resources = [host_sample()]
        started_at = time.time()
        with output.with_suffix(".log").open("w") as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            while True:
                try:
                    code = process.wait(timeout=2)
                    resources.append(host_sample())
                    if code:
                        raise subprocess.CalledProcessError(code, command)
                    break
                except subprocess.TimeoutExpired:
                    resources.append(host_sample())
        finished_at = time.time()
        report = json.loads(output.read_text())
        manifest["cases"].append({"variant": client, "workload": workload, "repetition": rep,
                                  "network": network,
                                  "file": output.name, "command": command,
                                  "library_path": env["TYPESAFE_BENCH_PATH"], "erl_flags": env["ERL_FLAGS"],
                                  "network_environment": {key: env[key] for key in
                                                          ["BENCH_PORT", "ERL_INETRC", "BENCH_FIXTURE_DESCRIPTION"]
                                                          if key in env},
                                  "fixture": report["environment"]["fixture"],
                                  "started_at": started_at, "finished_at": finished_at,
                                  "host_samples": resources})
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"{index}/{len(cases)} {client} {workload} {rate}/s {network or ''} "
              f"p99={report['success_latency_from_scheduled_arrival_ms']['p99']}ms "
              f"drops={report['driver_dropped']} outcomes={report['outcomes']}", flush=True)
    manifest["complete"] = True
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--clients", default="baseline,typesafe,finch,req,req_llm")
    parser.add_argument("--rates", default="6000,8000")
    parser.add_argument("--workloads", default="mixed")
    parser.add_argument("--connections", type=int, default=4)
    parser.add_argument("--seconds", type=int, default=15)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--seed", type=int, default=20260917)
    parser.add_argument("--storage", choices=["ets", "list"], default="ets")
    parser.add_argument("--network-pair", type=Path, nargs=2, metavar=("DIRECT_INETRC", "SSH_INETRC"),
                        help="Pair each case using these per-VM resolver files; one port and fixture for both")
    parser.add_argument("--output", type=Path, required=True)
    run(parser.parse_args())

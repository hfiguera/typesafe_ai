#!/usr/bin/env python3
"""Paired, randomized mixed-load comparisons, using a fresh BEAM for each case.

Run from bench/ with a separate fixture already running. Each report and the
manifest record exact commands/settings. No live API or credentials are used.
"""
import argparse
import json
import os
from pathlib import Path
import random
import subprocess

WORKLOADS = {"small": (256, 1, 0), "batch": (16384, 32, 0),
             "mixed": (65536, 1, 10), "large_mix": (524288, 1, 10)}


def run(args):
    assert args.repetitions > 0 and args.seconds > 0
    rates = [int(n) for n in args.rates.split(",")]
    assert all(n > 0 for n in rates)
    clients = args.clients.split(",")
    assert all(c in ["baseline", "typesafe", "finch", "req", "req_llm"] for c in clients)
    workloads = args.workloads.split(",")
    assert all(w in WORKLOADS for w in workloads)
    if "baseline" in clients:
        assert args.baseline and (args.baseline / "mix.exs").is_file()
    rng = random.Random(args.seed)
    cases = []
    for rep in range(1, args.repetitions + 1):
        block = [(rep, client, rate, workload) for client in clients for rate in rates for workload in workloads]
        rng.shuffle(block)
        cases.extend(block)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"complete": False, "seed": args.seed, "seconds": args.seconds,
                "repetitions": args.repetitions, "cases": [],
                "note": "Fresh client BEAM per case; fixture remains running. Baseline changes library path only."}
    manifest_path = args.output.with_suffix(".json")
    for index, (rep, client, rate, workload) in enumerate(cases, 1):
        state_bytes, questions, large_every = WORKLOADS[workload]
        output = Path(f"{args.output}-{client}-{workload}-{rate}-{rep}.json")
        env = os.environ.copy()
        env.setdefault("ERL_FLAGS", "+S 4:4")
        env["TYPESAFE_BENCH_PATH"] = str(args.baseline.resolve() if client == "baseline" else Path("..").resolve())
        command = ["mix", "run", "load.exs", "--client", "typesafe" if client == "baseline" else client,
                   "--rate", str(rate), "--requests", str(rate * args.seconds),
                   "--connections", "4", "--max-concurrency", "128", "--max-queue", "1024",
                   "--large-every", str(large_every), "--bytes", str(state_bytes),
                   "--questions", str(questions), "--sample-storage", args.storage,
                   "--output", str(output)]
        with output.with_suffix(".log").open("w") as log:
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        report = json.loads(output.read_text())
        manifest["cases"].append({"variant": client, "workload": workload, "repetition": rep,
                                  "file": output.name, "command": command,
                                  "library_path": env["TYPESAFE_BENCH_PATH"], "erl_flags": env["ERL_FLAGS"],
                                  "fixture": report["environment"]["fixture"]})
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"{index}/{len(cases)} {client} {workload} {rate}/s "
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
    parser.add_argument("--seconds", type=int, default=15)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--seed", type=int, default=20260917)
    parser.add_argument("--storage", choices=["ets", "list"], default="ets")
    parser.add_argument("--output", type=Path, required=True)
    run(parser.parse_args())

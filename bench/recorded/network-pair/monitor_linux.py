#!/usr/bin/env python3
"""Read-only Linux host/fixture observations; run separately from the client."""
import argparse
import json
from pathlib import Path
import time

from mixed_comparison import host_sample

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--pid", type=int, help="Optional fixture PID; omit for whole-host client observations")
parser.add_argument("--interface", required=True)
parser.add_argument("--seconds", type=int, default=1800)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()

with args.output.open("w") as output:
    for _ in range(args.seconds // 2):
        sample = host_sample()
        sample["host_cpu_ticks"] = Path("/proc/stat").read_text().splitlines()[0]
        sample["loadavg"] = Path("/proc/loadavg").read_text().strip()
        sample["fixture_pid"] = args.pid
        try:
            # Keep only CPU counters and RSS; never process arguments or environment.
            if args.pid is not None:
                fields = Path(f"/proc/{args.pid}/stat").read_text().rsplit(") ", 1)[1].split()
                sample["fixture"] = {"user_ticks": int(fields[11]), "system_ticks": int(fields[12]),
                                     "rss_pages": int(fields[21])}
        except FileNotFoundError:
            break
        sample["network"] = {
            key: int(Path(f"/sys/class/net/{args.interface}/statistics/{key}").read_text())
            for key in ["rx_bytes", "tx_bytes", "rx_dropped", "tx_dropped", "rx_errors", "tx_errors"]
        }
        output.write(json.dumps(sample) + "\n")
        output.flush()
        time.sleep(2)

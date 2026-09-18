#!/usr/bin/env python3
"""Join approximate host observations to fresh-VM comparison case windows."""
import argparse
import json
from pathlib import Path
from statistics import mean


def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def interval_stats(samples, linux):
    stats = []
    for before, after in zip(samples, samples[1:]):
        seconds = after["unix_seconds"] - before["unix_seconds"]
        if linux:
            # Guest ticks are already included in user/nice; exclude them here.
            a = [int(n) for n in before["host_cpu_ticks"].split()[1:9]]
            b = [int(n) for n in after["host_cpu_ticks"].split()[1:9]]
            total = sum(b) - sum(a)
            idle = b[3] + b[4] - a[3] - a[4]
            fixture_ticks = sum(after["fixture"][k] - before["fixture"][k]
                                for k in ["user_ticks", "system_ticks"])
            # The recorded Linux host reports CLK_TCK=100.
            fixture_cpu = fixture_ticks / seconds
            rx = (after["network"]["rx_bytes"] - before["network"]["rx_bytes"]) * 8 / seconds / 1e6
        else:
            a, b = before["cpu_ticks"], after["cpu_ticks"]
            total = sum(b.values()) - sum(a.values())
            idle = b["idle"] - a["idle"]
            fixture_cpu, rx = None, None
        if total > 0:
            stats.append({"host_cpu_percent": (total - idle) * 100 / total,
                          "fixture_cpu_percent": fixture_cpu, "rx_mbps": rx})
    return stats


def describe(samples, linux):
    if len(samples) < 2:
        raise ValueError("Insufficient host samples for a case")
    stats = interval_stats(samples, linux)
    summary = {"samples": len(samples),
               "host_cpu_mean_percent": mean(r["host_cpu_percent"] for r in stats),
               "host_cpu_max_interval_percent": max(r["host_cpu_percent"] for r in stats)}
    if linux:
        temp = "/sys/class/thermal/thermal_zone1/temp"
        counter = "/sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count"
        summary.update(
            package_temp_celsius_range=[min(s["sysfs"][temp] for s in samples) / 1000,
                                        max(s["sysfs"][temp] for s in samples) / 1000],
            package_throttle_delta=samples[-1]["sysfs"][counter] - samples[0]["sysfs"][counter],
            fixture_cpu_mean_percent=mean(r["fixture_cpu_percent"] for r in stats),
            fixture_cpu_max_interval_percent=max(r["fixture_cpu_percent"] for r in stats),
            rx_max_interval_mbps=max(r["rx_mbps"] for r in stats),
            network_error_drop_deltas={key: samples[-1]["network"][key] - samples[0]["network"][key]
                                       for key in ["rx_errors", "tx_errors", "rx_dropped", "tx_dropped"]})
    else:
        summary["thermal_states"] = sorted(set(s["thermal_state"] for s in samples))
    return summary


def summarize(manifest_path, mac_path, linux_path, clock_path):
    manifest = json.loads(manifest_path.read_text())
    if not manifest["complete"]:
        raise ValueError("Comparison is incomplete")
    mac, linux = rows(mac_path), rows(linux_path)
    offset = json.loads(clock_path.read_text())["remote_minus_local_midpoint_seconds"]

    def window(data, start, end):
        return [row for row in data if start <= row["unix_seconds"] <= end]

    start = min(c["started_at"] for c in manifest["cases"])
    end = max(c["finished_at"] for c in manifest["cases"])
    report = {"scope": "Whole case process lifetime, including startup/warmup/aggregation; 2 s samples. CPU percentages cover the whole host except fixture CPU, where 100% means one CPU. Clock alignment is approximate; overall windows padded by 2 s.",
              "linux_clock_offset_seconds": offset, "start_unix_mac": start, "end_unix_mac": end,
              "mac_client": describe(window(mac, start - 2, end + 2), False),
              "linux_server": describe(window(linux, start + offset - 2, end + offset + 2), True),
              "cases": []}
    for case in manifest["cases"]:
        start, end = case["started_at"], case["finished_at"]
        report["cases"].append({"file": case["file"], "variant": case["variant"],
                                "mac_client": describe(window(mac, start, end), False),
                                "linux_server": describe(window(linux, start + offset, end + offset), True)})
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("mac_monitor", type=Path)
    parser.add_argument("linux_monitor", type=Path)
    parser.add_argument("clock_check", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(summarize(args.manifest, args.mac_monitor,
                                              args.linux_monitor, args.clock_check), indent=2) + "\n")

## mac-curves

288 scenarios; 3,816,000 offered; 0 client/driver errors; 324,950 driver drops.

Highest tested offered rate with a contiguous passing prefix, **every repetition passing**. This is a finite local experiment, not sustained production capacity. `—` means no qualifying prefix.

| Workload | Connections | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---:|---:|---:|
| batch | 1 | 8000 | 2000 | — | 2000 |
| batch | 4 | 500 | 16000 | — | 500 |
| mixed | 1 | 500 | 2000 | 8000 | 2000 |
| mixed | 4 | 16000 | 2000 | 500 | 8000 |
| small | 1 | 16000 | — | 2000 | 8000 |
| small | 4 | 500 | — | 2000 | — |

Scheduled-arrival p99 in ms: **median [min–max] across runs**, followed by passing repetitions / total. These are distributions of run percentiles, not a pooled percentile.

| Workload | Connections | Offered req/s | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---|---|---|---|
| batch | 1 | 500 | 10.88 [10.52–12.12]; 3/3 | 9.96 [9.14–10.23]; 3/3 | 10.43 [10.27–16.38]; 2/3 | 10.95 [10.44–18.24]; 3/3 |
| batch | 1 | 2000 | 10.62 [9.31–15.78]; 3/3 | 9.08 [7.50–12.97]; 3/3 | 8.59 [7.91–9.84]; 3/3 | 10.85 [9.01–12.01]; 3/3 |
| batch | 1 | 8000 | 7.75 [7.71–7.88]; 3/3 | 20.16 [7.57–26.82]; 1/3 | 13.53 [8.32–18.90]; 3/3 | 70.61 [55.62–72.89]; 0/3 |
| batch | 1 | 16000 | 41.54 [40.77–41.69]; 0/3 | 42.04 [40.42–44.26]; 0/3 | 42.64 [42.19–42.65]; 0/3 | 108.86 [98.94–113.91]; 0/3 |
| batch | 4 | 500 | 12.96 [8.56–13.20]; 3/3 | 12.96 [11.96–15.23]; 3/3 | 15.05 [13.10–16.51]; 2/3 | 13.66 [11.04–14.32]; 3/3 |
| batch | 4 | 2000 | 14.78 [9.69–15.75]; 2/3 | 13.65 [12.18–16.85]; 3/3 | 14.01 [11.02–16.88]; 2/3 | 11.58 [8.09–23.17]; 2/3 |
| batch | 4 | 8000 | 13.35 [12.09–14.88]; 3/3 | 10.81 [10.53–14.66]; 3/3 | 13.64 [8.95–15.32]; 3/3 | 55.12 [11.29–66.48]; 1/3 |
| batch | 4 | 16000 | 9.29 [7.81–9.85]; 3/3 | 8.51 [8.29–9.68]; 3/3 | 8.93 [8.74–10.05]; 3/3 | 168.84 [161.37–180.40]; 0/3 |
| mixed | 1 | 500 | 13.63 [11.22–14.79]; 3/3 | 9.52 [8.82–12.05]; 3/3 | 12.03 [8.86–14.09]; 3/3 | 10.92 [9.96–10.97]; 3/3 |
| mixed | 1 | 2000 | 11.67 [10.38–23.70]; 2/3 | 11.20 [10.50–12.04]; 3/3 | 9.56 [9.48–10.78]; 3/3 | 8.95 [7.91–11.38]; 3/3 |
| mixed | 1 | 8000 | 7.69 [7.64–8.43]; 3/3 | 8.51 [7.80–37.03]; 2/3 | 7.95 [7.66–8.02]; 3/3 | 20.14 [8.28–62.43]; 1/3 |
| mixed | 1 | 16000 | 39.53 [39.20–39.93]; 0/3 | 102.34 [100.46–105.41]; 0/3 | 105.82 [100.41–107.60]; 0/3 | 133.83 [129.15–137.27]; 0/3 |
| mixed | 4 | 500 | 9.74 [9.71–13.65]; 3/3 | 13.55 [11.75–15.85]; 3/3 | 14.35 [9.14–14.71]; 3/3 | 11.05 [10.38–13.96]; 3/3 |
| mixed | 4 | 2000 | 10.04 [8.61–15.03]; 3/3 | 13.93 [13.18–14.83]; 3/3 | 14.37 [11.50–18.44]; 2/3 | 9.58 [7.75–9.98]; 3/3 |
| mixed | 4 | 8000 | 11.24 [9.20–13.98]; 3/3 | 14.20 [12.62–16.59]; 2/3 | 16.11 [14.16–18.72]; 1/3 | 7.81 [7.79–7.85]; 3/3 |
| mixed | 4 | 16000 | 14.83 [8.13–17.16]; 3/3 | 7.78 [7.67–10.20]; 3/3 | 8.74 [7.80–9.40]; 3/3 | 129.94 [122.62–135.72]; 0/3 |
| small | 1 | 500 | 8.84 [8.34–11.63]; 3/3 | 8.99 [8.97–20.88]; 2/3 | 8.86 [8.37–11.68]; 3/3 | 12.96 [9.63–13.89]; 3/3 |
| small | 1 | 2000 | 10.02 [8.35–11.95]; 3/3 | 9.94 [9.09–10.29]; 3/3 | 9.66 [8.90–10.54]; 3/3 | 9.66 [8.16–9.78]; 3/3 |
| small | 1 | 8000 | 11.20 [7.31–14.95]; 3/3 | 8.83 [7.61–13.58]; 3/3 | 11.94 [7.85–20.99]; 2/3 | 8.24 [7.73–8.55]; 3/3 |
| small | 1 | 16000 | 9.99 [7.89–13.99]; 3/3 | 22.57 [13.80–22.91]; 1/3 | 19.86 [10.00–21.11]; 1/3 | 40.33 [37.43–42.05]; 0/3 |
| small | 4 | 500 | 8.81 [8.77–9.12]; 3/3 | 16.92 [9.41–17.94]; 2/3 | 11.75 [10.14–11.92]; 3/3 | 14.23 [13.98–17.15]; 2/3 |
| small | 4 | 2000 | 14.82 [14.20–16.65]; 1/3 | 12.29 [9.84–24.15]; 2/3 | 12.12 [10.38–14.96]; 3/3 | 12.57 [11.79–19.21]; 2/3 |
| small | 4 | 8000 | 15.61 [13.09–27.73]; 2/3 | 14.23 [12.66–20.33]; 2/3 | 13.70 [12.86–15.47]; 2/3 | 9.24 [7.95–11.99]; 3/3 |
| small | 4 | 16000 | 18.11 [10.23–18.66]; 2/3 | 8.26 [8.05–21.29]; 2/3 | 13.02 [10.74–33.31]; 2/3 | 10.37 [10.00–15.62]; 3/3 |

Failures and resource diagnostics across all rates. CPU covers the whole client VM, including the generator. Memory is end-of-run snapshots, not peaks.

| Client | Successful calls | Errors | Driver drops | VM CPU ms / 1,000 successes | Largest end snapshot (MiB) |
|---|---:|---:|---:|---:|---:|
| typesafe | 933,524 | 0 | 20,476 | 107.4 | 125.5 |
| finch | 894,552 | 0 | 59,448 | 122.2 | 128.3 |
| req | 891,881 | 0 | 62,119 | 122.7 | 126.3 |
| req_llm | 771,093 | 0 | 182,907 | 275.7 | 171.6 |

## linux-curves

288 scenarios; 1,584,000 offered; 0 client/driver errors; 135,628 driver drops.

Highest tested offered rate with a contiguous passing prefix, **every repetition passing**. This is a finite local experiment, not sustained production capacity. `—` means no qualifying prefix.

| Workload | Connections | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---:|---:|---:|
| batch | 1 | 1500 | 1500 | 1500 | 1500 |
| batch | 4 | 3000 | 3000 | 1500 | 500 |
| mixed | 1 | 3000 | 3000 | 1500 | 1500 |
| mixed | 4 | 3000 | 6000 | 6000 | 1500 |
| small | 1 | 1500 | 3000 | 3000 | 1500 |
| small | 4 | 3000 | 3000 | 6000 | 1500 |

Scheduled-arrival p99 in ms: **median [min–max] across runs**, followed by passing repetitions / total. These are distributions of run percentiles, not a pooled percentile.

| Workload | Connections | Offered req/s | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---|---|---|---|
| batch | 1 | 500 | 8.91 [8.84–8.94]; 3/3 | 8.99 [8.60–9.20]; 3/3 | 8.96 [8.48–9.11]; 3/3 | 8.95 [8.36–10.45]; 3/3 |
| batch | 1 | 1500 | 8.36 [7.19–9.08]; 3/3 | 7.95 [7.70–8.96]; 3/3 | 8.77 [8.62–9.25]; 3/3 | 9.96 [9.92–12.77]; 3/3 |
| batch | 1 | 3000 | 12.04 [8.54–48.75]; 2/3 | 8.74 [8.49–55.80]; 2/3 | 11.48 [8.59–21.98]; 2/3 | 232.37 [140.72–259.20]; 0/3 |
| batch | 1 | 6000 | 113.12 [99.73–116.88]; 0/3 | 105.73 [100.82–138.38]; 0/3 | 140.11 [94.69–150.25]; 0/3 | 214.38 [203.34–276.36]; 0/3 |
| batch | 4 | 500 | 8.77 [8.67–9.15]; 3/3 | 9.96 [9.03–10.73]; 3/3 | 9.46 [9.06–9.51]; 3/3 | 9.18 [8.92–10.97]; 3/3 |
| batch | 4 | 1500 | 8.08 [8.04–8.89]; 3/3 | 8.24 [8.10–8.30]; 3/3 | 9.21 [8.22–9.24]; 3/3 | 14.42 [10.03–26.55]; 2/3 |
| batch | 4 | 3000 | 8.65 [8.21–10.01]; 3/3 | 8.40 [8.40–11.65]; 3/3 | 21.09 [17.77–24.43]; 1/3 | 291.13 [59.24–743.34]; 0/3 |
| batch | 4 | 6000 | 9.77 [8.92–97.73]; 2/3 | 15.68 [9.26–125.83]; 2/3 | 68.74 [8.92–195.20]; 1/3 | 511.49 [391.64–532.18]; 0/3 |
| mixed | 1 | 500 | 9.19 [8.88–9.31]; 3/3 | 8.82 [8.41–8.97]; 3/3 | 9.07 [8.79–9.12]; 3/3 | 9.89 [9.30–9.97]; 3/3 |
| mixed | 1 | 1500 | 8.54 [8.06–8.62]; 3/3 | 8.18 [8.16–8.44]; 3/3 | 8.38 [8.31–8.91]; 3/3 | 9.87 [9.55–17.03]; 3/3 |
| mixed | 1 | 3000 | 7.18 [7.03–8.05]; 3/3 | 7.29 [7.08–10.72]; 3/3 | 37.63 [7.70–75.82]; 1/3 | 247.82 [10.26–273.25]; 1/3 |
| mixed | 1 | 6000 | 48.43 [32.91–126.24]; 0/3 | 260.72 [182.49–266.70]; 0/3 | 257.35 [208.05–294.15]; 0/3 | 323.23 [292.42–450.20]; 0/3 |
| mixed | 4 | 500 | 8.99 [8.56–9.09]; 3/3 | 8.88 [8.63–8.92]; 3/3 | 9.15 [9.05–9.72]; 3/3 | 9.91 [9.82–9.92]; 3/3 |
| mixed | 4 | 1500 | 8.22 [8.18–8.35]; 3/3 | 8.29 [8.04–8.84]; 3/3 | 8.48 [7.02–8.79]; 3/3 | 9.10 [9.01–9.68]; 3/3 |
| mixed | 4 | 3000 | 8.49 [8.46–9.32]; 3/3 | 8.40 [8.36–8.66]; 3/3 | 8.41 [8.14–8.42]; 3/3 | 10.80 [9.19–45.15]; 2/3 |
| mixed | 4 | 6000 | 27.24 [25.36–34.47]; 0/3 | 8.99 [8.51–12.38]; 3/3 | 7.89 [7.61–8.96]; 3/3 | 415.63 [383.54–535.16]; 0/3 |
| small | 1 | 500 | 8.21 [7.98–8.29]; 3/3 | 8.36 [8.32–8.41]; 3/3 | 8.27 [8.26–8.34]; 3/3 | 8.67 [8.61–9.03]; 3/3 |
| small | 1 | 1500 | 7.69 [6.81–8.26]; 3/3 | 8.10 [7.72–8.15]; 3/3 | 8.16 [8.12–8.26]; 3/3 | 9.09 [9.00–9.12]; 3/3 |
| small | 1 | 3000 | 7.55 [6.74–20.44]; 2/3 | 11.12 [8.75–17.85]; 3/3 | 7.71 [6.95–16.82]; 3/3 | 9.24 [8.91–41.90]; 2/3 |
| small | 1 | 6000 | 27.35 [9.07–38.52]; 1/3 | 11.93 [7.95–63.99]; 2/3 | 51.54 [21.33–79.71]; 0/3 | 127.13 [104.20–139.61]; 0/3 |
| small | 4 | 500 | 8.93 [8.21–9.04]; 3/3 | 8.46 [8.21–8.79]; 3/3 | 8.69 [8.62–9.11]; 3/3 | 8.72 [8.64–10.51]; 3/3 |
| small | 4 | 1500 | 8.01 [7.99–8.33]; 3/3 | 8.64 [8.57–8.66]; 3/3 | 8.34 [7.94–8.35]; 3/3 | 9.24 [9.22–9.32]; 3/3 |
| small | 4 | 3000 | 8.24 [8.24–8.25]; 3/3 | 8.34 [8.07–8.42]; 3/3 | 8.43 [8.31–8.48]; 3/3 | 9.56 [9.16–61.42]; 2/3 |
| small | 4 | 6000 | 10.77 [8.32–26.13]; 2/3 | 34.70 [32.30–35.64]; 0/3 | 8.43 [7.81–8.60]; 3/3 | 245.69 [76.05–328.91]; 0/3 |

Failures and resource diagnostics across all rates. CPU covers the whole client VM, including the generator. Memory is end-of-run snapshots, not peaks.

| Client | Successful calls | Errors | Driver drops | VM CPU ms / 1,000 successes | Largest end snapshot (MiB) |
|---|---:|---:|---:|---:|---:|
| typesafe | 389,706 | 0 | 6,294 | 544.9 | 110.1 |
| finch | 374,610 | 0 | 21,390 | 563.6 | 114.9 |
| req | 372,970 | 0 | 23,030 | 584.8 | 110.6 |
| req_llm | 311,086 | 0 | 84,914 | 1171.9 | 155.5 |

## mac-confirmation

12 scenarios; 720,000 offered; 0 client/driver errors; 0 driver drops.

Highest tested offered rate with a contiguous passing prefix, **every repetition passing**. This is a finite local experiment, not sustained production capacity. `—` means no qualifying prefix.

| Workload | Connections | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---:|---:|---:|
| small | 4 | — | 2000 | — | — |

Scheduled-arrival p99 in ms: **median [min–max] across runs**, followed by passing repetitions / total. These are distributions of run percentiles, not a pooled percentile.

| Workload | Connections | Offered req/s | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---|---|---|---|
| small | 4 | 2000 | 12.57 [11.76–19.57]; 2/3 | 10.94 [10.65–13.00]; 3/3 | 13.34 [11.72–24.73]; 2/3 | 13.85 [13.67–30.65]; 2/3 |

Failures and resource diagnostics across all rates. CPU covers the whole client VM, including the generator. Memory is end-of-run snapshots, not peaks.

| Client | Successful calls | Errors | Driver drops | VM CPU ms / 1,000 successes | Largest end snapshot (MiB) |
|---|---:|---:|---:|---:|---:|
| typesafe | 180,000 | 0 | 0 | 127.1 | 127.7 |
| finch | 180,000 | 0 | 0 | 145.7 | 127.5 |
| req | 180,000 | 0 | 0 | 143.5 | 127.6 |
| req_llm | 180,000 | 0 | 0 | 299.3 | 124.1 |

## linux-confirmation

12 scenarios; 540,000 offered; 0 client/driver errors; 0 driver drops.

Highest tested offered rate with a contiguous passing prefix, **every repetition passing**. This is a finite local experiment, not sustained production capacity. `—` means no qualifying prefix.

| Workload | Connections | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---:|---:|---:|
| small | 4 | 1500 | 1500 | 1500 | 1500 |

Scheduled-arrival p99 in ms: **median [min–max] across runs**, followed by passing repetitions / total. These are distributions of run percentiles, not a pooled percentile.

| Workload | Connections | Offered req/s | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---|---|---|---|
| small | 4 | 1500 | 7.36 [7.31–7.38]; 3/3 | 7.45 [7.20–7.64]; 3/3 | 7.15 [7.14–7.15]; 3/3 | 9.27 [9.03–9.53]; 3/3 |

Failures and resource diagnostics across all rates. CPU covers the whole client VM, including the generator. Memory is end-of-run snapshots, not peaks.

| Client | Successful calls | Errors | Driver drops | VM CPU ms / 1,000 successes | Largest end snapshot (MiB) |
|---|---:|---:|---:|---:|---:|
| typesafe | 135,000 | 0 | 0 | 365.6 | 111.2 |
| finch | 135,000 | 0 | 0 | 496.9 | 111.5 |
| req | 135,000 | 0 | 0 | 390.3 | 109.1 |
| req_llm | 135,000 | 0 | 0 | 1768.5 | 107.7 |

## linux-mixed-followup

12 scenarios; 1,080,000 offered; 1,519 client/driver errors; 333,431 driver drops.

Highest tested offered rate with a contiguous passing prefix, **every repetition passing**. This is a finite local experiment, not sustained production capacity. `—` means no qualifying prefix.

| Workload | Connections | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---:|---:|---:|
| mixed | 4 | — | — | — | — |

Scheduled-arrival p99 in ms: **median [min–max] across runs**, followed by passing repetitions / total. These are distributions of run percentiles, not a pooled percentile.

| Workload | Connections | Offered req/s | TypeSafe | Finch | Req | ReqLLM |
|---|---:|---:|---|---|---|---|
| mixed | 4 | 6000 | 137.73 [8.35–169.51]; 1/3 | 489.69 [462.42–543.81]; 0/3 | 529.85 [468.58–587.39]; 0/3 | 902.01 [806.89–941.59]; 0/3 |

Failures and resource diagnostics across all rates. CPU covers the whole client VM, including the generator. Memory is end-of-run snapshots, not peaks.

| Client | Successful calls | Errors | Driver drops | VM CPU ms / 1,000 successes | Largest end snapshot (MiB) |
|---|---:|---:|---:|---:|---:|
| typesafe | 266,259 | 0 | 3,741 | 555.0 | 125.0 |
| finch | 190,993 | 0 | 79,007 | 775.8 | 124.0 |
| req | 189,035 | 6 | 80,959 | 774.0 | 123.1 |
| req_llm | 98,763 | 1,513 | 169,724 | 1684.1 | 120.4 |

## mac-live-curves

16 scenarios; 128 offered; 0 client/driver errors; 0 driver drops.

Small live sample: median of each run's p50 and full observed p99 range. The latter is nearly a maximum for eight calls; **not a tail-latency estimate**.

| Client | Offered req/s | Measured calls | Run p50 median (ms) | Observed run p99 range (ms) |
|---|---:|---:|---:|---:|
| finch | 1 | 16 | 118.13 | 147.09–156.28 |
| finch | 4 | 16 | 114.82 | 228.21–269.93 |
| req | 1 | 16 | 117.47 | 160.80–177.35 |
| req | 4 | 16 | 108.25 | 399.37–468.51 |
| req_llm | 1 | 16 | 132.43 | 164.08–357.78 |
| req_llm | 4 | 16 | 149.66 | 258.06–337.00 |
| typesafe | 1 | 16 | 123.70 | 158.81–244.39 |
| typesafe | 4 | 16 | 123.80 | 193.01–205.03 |

Observed usage, including warmup: {'input_tokens': 42480, 'output_tokens': 3024}. Models: ['jev-1.13.0'].

# Recorded latency tables

Generated by `summarize_curves.py`; see [LATENCY.md](LATENCY.md) for interpretation.

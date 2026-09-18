# Community SDK screen: complete tables

12 ten-second cases; 60,000 offered evaluations plus 1,200 warmups. Offline replay only.

p99 is measured from scheduled arrival. CPU includes the client VM and driver. CPU is ms per 1000 successful requests. Rows summarize repetitions, not pooled requests. Passes require all offered requests to succeed, no driver drops, at least 1000 successes, p99 ≤20 ms, launch-lag p99 ≤5 ms, and ≥99% of arrivals completed within 20 ms. Host health is reported separately; this short screen does not establish maximum capacity.

## defaults

| Shape / req/s | Client | p99 median (range), ms | Launch lag p99 range, ms | CPU median | Successful req/s median | Errors / drops | Passes |
|---|---|---:|---:|---:|---:|---:|---:|
| noul_small / 500 | jev | 8.91 (8.66–9.42) | 1.15–1.74 | 800.6 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe | 8.50 (8.24–9.27) | 1.01–1.97 | 411.8 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe_api | 9.40 (9.39–10.03) | 1.71–2.04 | 828.4 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe_sdk | 9.37 (9.02–9.83) | 1.20–1.65 | 1166.2 | 499.7 | 0 / 0 | 3/3 |

## Every repetition

| Case | p50 / p95 / p99, ms | Lag p99, ms | CPU ms | Outcomes | Drops |
|---|---:|---:|---:|---|---:|
| defaults-typesafe_api-noul_small-500 #1 | 7.88 / 9.13 / 9.40 | 1.80 | 4235 | {'ok': 5000} | 0 |
| defaults-typesafe_sdk-noul_small-500 #1 | 8.42 / 8.83 / 9.83 | 1.65 | 6195 | {'ok': 5000} | 0 |
| defaults-jev-noul_small-500 #1 | 7.71 / 8.42 / 8.66 | 1.15 | 3526 | {'ok': 5000} | 0 |
| defaults-typesafe-noul_small-500 #1 | 7.52 / 8.34 / 8.50 | 1.48 | 2059 | {'ok': 5000} | 0 |
| defaults-typesafe-noul_small-500 #2 | 7.33 / 7.55 / 8.24 | 1.01 | 2049 | {'ok': 5000} | 0 |
| defaults-typesafe_sdk-noul_small-500 #2 | 8.08 / 8.36 / 9.37 | 1.23 | 5831 | {'ok': 5000} | 0 |
| defaults-jev-noul_small-500 #2 | 7.63 / 8.68 / 8.91 | 1.21 | 4003 | {'ok': 5000} | 0 |
| defaults-typesafe_api-noul_small-500 #2 | 7.75 / 9.11 / 10.03 | 2.04 | 4135 | {'ok': 5000} | 0 |
| defaults-typesafe_api-noul_small-500 #3 | 7.33 / 8.49 / 9.39 | 1.71 | 4142 | {'ok': 5000} | 0 |
| defaults-jev-noul_small-500 #3 | 7.96 / 9.16 / 9.42 | 1.74 | 4166 | {'ok': 5000} | 0 |
| defaults-typesafe_sdk-noul_small-500 #3 | 8.33 / 8.68 / 9.02 | 1.20 | 5185 | {'ok': 5000} | 0 |
| defaults-typesafe-noul_small-500 #3 | 7.86 / 9.01 / 9.27 | 1.97 | 2183 | {'ok': 5000} | 0 |

# Community SDK screen: complete tables

36 ten-second cases; 180,000 offered evaluations plus 3,600 warmups. Offline replay only.

p99 is measured from scheduled arrival. CPU includes the client VM and driver. CPU is ms per 1000 successful requests. Rows summarize repetitions, not pooled requests. Passes require all offered requests to succeed, no driver drops, at least 1000 successes, p99 ≤20 ms, launch-lag p99 ≤5 ms, and ≥99% of arrivals completed within 20 ms. Host health is reported separately; this short screen does not establish maximum capacity.

## matched

| Shape / req/s | Client | p99 median (range), ms | Launch lag p99 range, ms | CPU median | Successful req/s median | Errors / drops | Passes |
|---|---|---:|---:|---:|---:|---:|---:|
| batch_32 / 500 | jev | 12.38 (11.97–12.48) | 1.57–2.10 | 1098.0 | 499.6 | 0 / 0 | 3/3 |
| batch_32 / 500 | typesafe | 12.48 (12.16–12.66) | 1.53–2.00 | 1057.6 | 499.6 | 0 / 0 | 3/3 |
| batch_32 / 500 | typesafe_api | 14.65 (12.51–14.73) | 1.26–1.47 | 1592.6 | 499.6 | 0 / 0 | 3/3 |
| noul_small / 500 | jev | 9.93 (9.88–10.41) | 1.35–1.50 | 529.0 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe | 10.01 (9.07–10.85) | 1.20–2.10 | 473.6 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe_api | 9.68 (9.08–11.06) | 1.21–1.76 | 768.0 | 499.7 | 0 / 0 | 3/3 |
| score_ten / 500 | jev | 10.54 (9.97–10.70) | 1.13–1.95 | 522.0 | 499.7 | 0 / 0 | 3/3 |
| score_ten / 500 | typesafe | 9.68 (8.85–11.83) | 1.20–1.89 | 456.6 | 499.7 | 0 / 0 | 3/3 |
| score_ten / 500 | typesafe_api | 10.20 (9.63–12.12) | 1.24–1.82 | 816.8 | 499.7 | 0 / 0 | 3/3 |

## defaults

| Shape / req/s | Client | p99 median (range), ms | Launch lag p99 range, ms | CPU median | Successful req/s median | Errors / drops | Passes |
|---|---|---:|---:|---:|---:|---:|---:|
| noul_small / 500 | jev | 9.95 (9.07–10.96) | 1.36–1.56 | 754.4 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe | 9.37 (8.97–10.20) | 1.46–1.89 | 398.8 | 499.7 | 0 / 0 | 3/3 |
| noul_small / 500 | typesafe_api | 11.39 (9.90–11.87) | 1.51–1.72 | 849.8 | 499.7 | 0 / 0 | 3/3 |

## Every repetition

| Case | p50 / p95 / p99, ms | Lag p99, ms | CPU ms | Outcomes | Drops |
|---|---:|---:|---:|---|---:|
| defaults-typesafe_api-noul_small-500 #1 | 8.08 / 9.01 / 9.90 | 1.72 | 4249 | {'ok': 5000} | 0 |
| matched-typesafe_api-noul_small-500 #1 | 7.85 / 8.78 / 9.08 | 1.24 | 3776 | {'ok': 5000} | 0 |
| defaults-typesafe-noul_small-500 #1 | 7.68 / 8.67 / 8.97 | 1.46 | 1916 | {'ok': 5000} | 0 |
| matched-typesafe-score_ten-500 #1 | 7.64 / 8.58 / 8.85 | 1.89 | 2247 | {'ok': 5000} | 0 |
| defaults-jev-noul_small-500 #1 | 8.13 / 9.34 / 10.96 | 1.44 | 3554 | {'ok': 5000} | 0 |
| matched-jev-score_ten-500 #1 | 8.11 / 9.10 / 10.54 | 1.37 | 3014 | {'ok': 5000} | 0 |
| matched-typesafe_api-batch_32-500 #1 | 9.72 / 11.97 / 14.73 | 1.47 | 8091 | {'ok': 5000} | 0 |
| matched-jev-batch_32-500 #1 | 8.81 / 10.70 / 11.97 | 2.10 | 6187 | {'ok': 5000} | 0 |
| matched-typesafe-noul_small-500 #1 | 7.35 / 9.15 / 10.85 | 1.58 | 2476 | {'ok': 5000} | 0 |
| matched-typesafe_api-score_ten-500 #1 | 8.45 / 9.85 / 12.12 | 1.24 | 3583 | {'ok': 5000} | 0 |
| matched-typesafe-batch_32-500 #1 | 8.62 / 10.53 / 12.66 | 1.64 | 4730 | {'ok': 5000} | 0 |
| matched-jev-noul_small-500 #1 | 7.93 / 9.07 / 10.41 | 1.35 | 2645 | {'ok': 5000} | 0 |
| defaults-typesafe-noul_small-500 #2 | 7.88 / 9.20 / 10.20 | 1.86 | 2034 | {'ok': 5000} | 0 |
| matched-typesafe_api-batch_32-500 #2 | 9.47 / 11.15 / 14.65 | 1.26 | 7963 | {'ok': 5000} | 0 |
| matched-jev-noul_small-500 #2 | 8.02 / 8.98 / 9.93 | 1.50 | 2573 | {'ok': 5000} | 0 |
| matched-typesafe-batch_32-500 #2 | 8.90 / 10.82 / 12.48 | 2.00 | 5458 | {'ok': 5000} | 0 |
| matched-typesafe-noul_small-500 #2 | 7.53 / 8.45 / 9.07 | 1.20 | 2368 | {'ok': 5000} | 0 |
| matched-jev-batch_32-500 #2 | 8.82 / 10.56 / 12.38 | 1.57 | 5388 | {'ok': 5000} | 0 |
| defaults-jev-noul_small-500 #2 | 8.22 / 9.03 / 9.95 | 1.56 | 3772 | {'ok': 5000} | 0 |
| defaults-typesafe_api-noul_small-500 #2 | 8.49 / 9.75 / 11.39 | 1.55 | 3925 | {'ok': 5000} | 0 |
| matched-typesafe-score_ten-500 #2 | 7.61 / 8.80 / 9.68 | 1.20 | 2283 | {'ok': 5000} | 0 |
| matched-jev-score_ten-500 #2 | 7.55 / 8.75 / 9.97 | 1.95 | 2610 | {'ok': 5000} | 0 |
| matched-typesafe_api-score_ten-500 #2 | 8.01 / 9.35 / 10.20 | 1.46 | 4204 | {'ok': 5000} | 0 |
| matched-typesafe_api-noul_small-500 #2 | 8.05 / 9.41 / 11.06 | 1.76 | 3876 | {'ok': 5000} | 0 |
| matched-typesafe-score_ten-500 #3 | 7.74 / 9.00 / 11.83 | 1.22 | 2412 | {'ok': 5000} | 0 |
| matched-jev-batch_32-500 #3 | 8.72 / 10.81 / 12.48 | 1.97 | 5490 | {'ok': 5000} | 0 |
| matched-typesafe-batch_32-500 #3 | 8.92 / 10.42 / 12.16 | 1.53 | 5288 | {'ok': 5000} | 0 |
| matched-typesafe-noul_small-500 #3 | 7.88 / 9.18 / 10.01 | 2.10 | 1906 | {'ok': 5000} | 0 |
| matched-typesafe_api-batch_32-500 #3 | 9.18 / 10.85 / 12.51 | 1.47 | 7531 | {'ok': 5000} | 0 |
| matched-typesafe_api-noul_small-500 #3 | 8.24 / 8.71 / 9.68 | 1.21 | 3840 | {'ok': 5000} | 0 |
| matched-jev-score_ten-500 #3 | 7.66 / 8.82 / 10.70 | 1.13 | 2541 | {'ok': 5000} | 0 |
| defaults-typesafe_api-noul_small-500 #3 | 8.30 / 9.79 / 11.87 | 1.51 | 4635 | {'ok': 5000} | 0 |
| matched-jev-noul_small-500 #3 | 8.18 / 8.90 / 9.88 | 1.44 | 3172 | {'ok': 5000} | 0 |
| defaults-jev-noul_small-500 #3 | 8.04 / 8.67 / 9.07 | 1.36 | 3958 | {'ok': 5000} | 0 |
| matched-typesafe_api-score_ten-500 #3 | 7.65 / 8.59 / 9.63 | 1.82 | 4084 | {'ok': 5000} | 0 |
| defaults-typesafe-noul_small-500 #3 | 7.79 / 9.16 / 9.37 | 1.89 | 1994 | {'ok': 5000} | 0 |

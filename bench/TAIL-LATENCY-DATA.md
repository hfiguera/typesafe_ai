# Tail-latency investigation: complete tables

Cells show median [min–max] of run statistics, not pooled percentiles.
CPU includes the client VM and arrival driver. Process CPU also includes startup, warmup and aggregation.
Pass requires zero errors/drops, ≥1000 successes, scheduled p99 ≤20 ms, launch-lag p99 ≤5 ms, and ≥99% of offered calls within 20 ms.
Timer controls and instrumented profiles are diagnostics, not client performance claims.

## mac-timer

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| default | 19.524 [14.104–562.681] | 10.592 [6.751–551.316] | 28.800 [23.600–29.200] | 1.244 [1.108–1.307] | 0 / 0 | n/a |
| no_spin | 7.646 [7.560–7.929] | 1.685 [1.614–1.964] | 22.400 [21.400–23.600] | 1.052 [1.049–1.063] | 0 / 0 | n/a |
| long_spin | 25.006 [20.925–101.619] | 16.624 [12.096–87.802] | 44.000 [42.000–51.800] | 1.568 [1.468–1.581] | 0 / 0 | n/a |
| one_scheduler | 8.018 [7.873–8.023] | 2.038 [1.929–2.093] | 21.600 [21.000–25.000] | 0.957 [0.931–0.983] | 0 / 0 | n/a |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## linux-timer

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| default | 7.307 [7.240–7.627] | 1.385 [1.319–1.696] | 302.400 [122.200–395.600] | 4.336 [3.172–4.647] | 0 / 0 | n/a |
| no_spin | 7.791 [7.161–7.951] | 1.865 [1.254–2.013] | 60.400 [15.200–92.200] | 2.249 [2.207–2.293] | 0 / 0 | n/a |
| long_spin | 10.624 [10.472–10.888] | 2.676 [2.455–2.716] | 458.800 [177.800–533.200] | 5.360 [3.935–5.742] | 0 / 0 | n/a |
| one_scheduler | 7.545 [7.515–7.951] | 1.615 [1.586–1.961] | 75.000 [60.000–77.400] | 2.357 [2.289–2.411] | 0 / 0 | n/a |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## screen

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| ts_default | 17.110 [14.834–19.747] | 7.100 [4.964–8.738] | 221.400 [204.200–245.400] | 3.106 [2.718–3.232] | 0 / 0 | 1/3 |
| llm_default | 14.487 [12.445–18.428] | 2.491 [1.715–6.653] | 537.200 [536.800–553.200] | 6.151 [6.050–6.257] | 0 / 0 | 2/3 |
| ts_no_spin | 17.973 [17.548–18.902] | 6.732 [5.690–7.592] | 241.200 [228.200–250.800] | 3.319 [3.111–3.325] | 0 / 0 | 0/3 |
| llm_no_spin | 16.825 [12.621–17.506] | 2.116 [1.824–2.752] | 504.800 [491.200–541.800] | 5.803 [5.718–5.842] | 0 / 0 | 3/3 |
| ts_long_spin | 17.254 [16.705–17.481] | 7.210 [5.975–7.393] | 272.600 [254.600–276.200] | 3.485 [3.383–3.676] | 0 / 0 | 0/3 |
| ts_pool1 | 14.558 [13.401–16.601] | 4.068 [2.823–5.278] | 218.400 [209.000–230.200] | 2.762 [2.717–2.875] | 0 / 0 | 2/3 |
| ts_pool8 | 14.696 [14.114–18.632] | 5.076 [5.049–8.080] | 246.800 [245.800–252.400] | 3.393 [3.288–3.578] | 0 / 0 | 0/3 |
| ts_scheduler1 | 14.877 [14.637–14.990] | 4.146 [3.854–4.288] | 229.000 [220.400–234.000] | 2.787 [2.747–2.803] | 0 / 0 | 3/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## runtime

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| ts_default | 16.119 [13.706–22.280] | 6.332 [3.893–9.773] | 230.600 [226.400–241.600] | 2.961 [2.938–3.239] | 0 / 0 | 1/3 |
| llm_default | 14.101 [11.696–20.441] | 2.447 [1.939–6.530] | 568.800 [553.800–570.400] | 6.408 [6.162–6.473] | 0 / 0 | 2/3 |
| ts_no_all_spin | 14.803 [12.866–23.513] | 3.686 [2.391–8.411] | 255.600 [222.400–257.400] | 3.074 [3.014–3.211] | 0 / 0 | 2/3 |
| llm_no_all_spin | 14.697 [11.026–17.062] | 1.851 [1.774–2.289] | 512.600 [433.800–520.200] | 5.595 [5.008–5.743] | 0 / 0 | 3/3 |
| ts_io_poll | 17.373 [15.601–25.375] | 8.183 [6.176–10.122] | 246.200 [204.400–253.000] | 3.505 [2.768–3.625] | 0 / 0 | 0/3 |
| llm_io_poll | 18.203 [13.677–23.720] | 6.546 [2.333–8.916] | 579.400 [578.000–642.000] | 6.633 [6.380–6.967] | 0 / 0 | 1/3 |
| ts_no_compact | 17.569 [16.785–17.851] | 6.719 [6.196–7.013] | 241.600 [219.000–241.800] | 3.390 [2.989–3.414] | 0 / 0 | 0/3 |
| ts_spin_io | 17.470 [16.514–18.114] | 5.423 [5.080–6.427] | 265.400 [248.800–270.400] | 3.305 [3.191–3.396] | 0 / 0 | 0/3 |
| llm_spin_io | 17.631 [14.565–18.635] | 2.455 [1.964–4.074] | 462.000 [461.600–465.800] | 5.440 [5.394–5.586] | 0 / 0 | 3/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## profile

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| cancel_profile | 17.835 [17.835–17.835] | 7.895 [7.895–7.895] | 249.400 [249.400–249.400] | 5.941 [5.941–5.941] | 0 / 0 | 0/1 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## candidate

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| ts_baseline | 13.427 [13.017–20.225] | 3.992 [3.415–9.037] | 231.200 [209.000–235.400] | 3.072 [2.798–3.145] | 0 / 0 | 2/3 |
| ts_async_timers | 16.492 [13.617–26.577] | 6.590 [4.355–10.340] | 235.800 [232.800–244.000] | 3.027 [2.831–3.160] | 0 / 0 | 1/3 |
| req_llm | 11.997 [10.808–20.251] | 2.120 [1.658–5.197] | 511.200 [435.800–554.600] | 5.866 [5.423–6.501] | 0 / 0 | 2/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## wakeup

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| ts_default | 13.901 [13.896–17.922] | 4.511 [4.388–8.272] | 239.200 [224.200–248.400] | 3.174 [2.984–3.192] | 0 / 0 | 2/3 |
| llm_default | 12.789 [10.363–21.202] | 2.644 [1.841–6.563] | 465.400 [424.600–477.800] | 5.539 [5.188–5.547] | 0 / 0 | 2/3 |
| ts_wakeup | 16.941 [15.011–23.191] | 6.935 [5.831–9.663] | 271.800 [257.600–297.600] | 3.912 [3.514–4.080] | 0 / 0 | 0/3 |
| ts_schedulers16 | 16.371 [14.764–21.892] | 7.288 [5.659–9.661] | 249.800 [217.600–255.400] | 4.351 [3.731–4.414] | 0 / 0 | 0/3 |
| ts_latency_tier0 | 15.771 [15.069–16.149] | 4.998 [4.495–6.813] | 243.200 [216.600–247.800] | 3.180 [2.927–3.187] | 0 / 0 | 2/3 |
| llm_latency_tier0 | 14.203 [14.200–16.292] | 3.223 [2.606–4.116] | 507.200 [504.800–565.000] | 5.857 [5.755–6.207] | 0 / 0 | 3/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## work

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| work_0 | 30.360 [21.221–432.269] | 20.700 [12.567–420.657] | 30.800 [25.200–31.200] | 1.268 [1.221–1.299] | 0 / 0 | n/a |
| work_300 | 32.797 [30.404–45.542] | 18.752 [18.376–24.831] | 259.600 [251.600–262.200] | 2.699 [2.671–2.731] | 0 / 0 | n/a |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## rate

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| typesafe_1000 | 12.388 [11.424–16.818] | 3.478 [2.645–6.463] | 227.400 [216.867–229.133] | 7.087 [7.007–7.288] | 0 / 0 | 2/3 |
| typesafe_4000 | 19.745 [16.931–53.828] | 7.956 [5.336–10.721] | 120.867 [116.983–129.800] | 13.174 [12.885–13.982] | 0 / 0 | 0/3 |
| req_llm_1000 | 21.375 [10.574–25.160] | 7.176 [1.839–9.136] | 431.000 [424.333–454.467] | 11.630 [11.480–12.012] | 0 / 0 | 1/3 |
| req_llm_4000 | 11.872 [9.127–23.613] | 1.914 [1.684–2.675] | 297.200 [272.750–310.267] | 24.929 [23.507–26.188] | 0 / 0 | 2/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## inline

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| ts_baseline | 10.614 [9.473–10.617] | 2.263 [1.916–2.366] | 232.000 [229.600–233.000] | 3.069 [3.046–3.073] | 0 / 0 | 3/3 |
| ts_inline_body | 15.337 [8.954–15.519] | 4.641 [1.479–5.118] | 219.000 [163.200–235.200] | 2.603 [2.163–2.693] | 0 / 0 | 2/3 |
| req_llm | 11.273 [10.095–19.578] | 2.213 [1.931–7.147] | 425.000 [414.600–434.000] | 5.163 [5.043–5.300] | 0 / 0 | 2/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

## confirm

| Variant | Scheduled p99 ms | Launch-lag p99 ms | VM CPU ms / 1000 successes | Process CPU seconds | Errors / drops | Passes |
|---|---:|---:|---:|---:|---:|---:|
| baseline_score_ten_1000 | 13.121 [11.223–20.882] | 2.959 [2.673–9.658] | 205.000 [175.533–226.667] | 6.084 [5.336–6.934] | 0 / 0 | 2/3 |
| inline_score_ten_1000 | 11.758 [10.775–14.720] | 2.644 [2.110–5.298] | 209.933 [201.200–222.800] | 6.092 [5.634–6.156] | 0 / 0 | 2/3 |
| req_llm_score_ten_1000 | 11.454 [10.620–20.765] | 2.053 [1.920–6.663] | 426.267 [424.867–449.667] | 11.344 [11.280–12.237] | 0 / 0 | 2/3 |
| baseline_score_ten_4000 | 18.496 [9.417–22.067] | 6.932 [1.784–8.987] | 120.250 [116.383–122.667] | 13.210 [12.483–13.605] | 0 / 0 | 1/3 |
| inline_score_ten_4000 | 21.510 [10.817–22.271] | 8.523 [2.412–9.716] | 111.933 [87.800–117.950] | 13.170 [9.049–14.404] | 0 / 0 | 1/3 |
| req_llm_score_ten_4000 | 11.601 [11.025–12.253] | 1.896 [1.763–1.952] | 275.133 [272.250–275.983] | 23.721 [23.337–23.822] | 0 / 0 | 3/3 |
| baseline_batch_32_1000 | 18.677 [10.221–18.688] | 4.694 [1.812–6.540] | 493.600 [428.800–496.000] | 11.140 [9.351–11.263] | 0 / 0 | 2/3 |
| inline_batch_32_1000 | 10.190 [9.478–13.489] | 1.623 [1.389–1.957] | 456.133 [428.467–507.667] | 10.033 [9.284–11.527] | 0 / 0 | 3/3 |
| req_llm_batch_32_1000 | 9.753 [9.569–10.032] | 1.511 [1.482–1.614] | 1156.800 [1148.200–1169.267] | 22.254 [22.193–22.679] | 0 / 0 | 3/3 |

Exact flags, commands, workload sizes and source fingerprints are retained in the raw manifest and case files.

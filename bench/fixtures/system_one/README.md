# Captured System One payloads

Captured 2026-09-17T22:55:58.089332Z from `https://api.typesafe.ai/v1/systemone`, requesting `jev-latest` over verified HTTPS/HTTP/2. The service returned `jev-1.13.0` for every case.

Inputs are synthetic, including the invoice, support ticket and warehouse examples. These are payload fixtures, not labeled accuracy examples or a production traffic distribution. Request and response files contain the exact JSON entity bodies. Authorization and arbitrary response headers are not retained; the manifest allows only content-type/content-encoding headers.

| Case | Questions | Types | Request bytes | Response bytes |
|---|---:|---|---:|---:|
| noul_small | 1 | noul × 1 | 175 | 119 |
| choice_small | 1 | choice × 1 | 460 | 205 |
| choice_wide | 1 | choice × 1 | 1,512 | 568 |
| score_short | 1 | score × 1 | 398 | 263 |
| score_ten | 1 | score × 1 | 811 | 897 |
| mixed_batch | 6 | choice × 2, noul × 2, score × 2 | 1,230 | 741 |
| batch_32 | 32 | choice × 10, noul × 11, score × 11 | 24,666 | 14,261 |
| large_state | 3 | choice × 1, noul × 1, score × 1 | 67,943 | 426 |

The manifest records checksums, resolved model, observed token usage, and one live capture duration per case. Those durations include service/network work and possibly connection setup; they are not stable latency estimates. Eight successful evaluations reported 29,112 input and 4,276 output tokens. The initial aborted capture attempt is retained separately in the [replay experiment evidence](../../recorded/recorded-replay/initial-capture-attempt.json); its usage is unknown.

Replay validates the semantic request against the captured input and returns the original response bytes. Changing state, questions or model produces HTTP 409; an unknown fixture ID produces HTTP 404. All adapters may serialize JSON differently, but must send the same JSON value. Response-byte checksums prevent silent fixture edits.

A chosen fixture delay remains synthetic. Replayed model identifiers and token counts are metadata from the capture, not new model execution or token consumption. No live key is needed for replay or tests.

See the [replay report](../../REPLAY.md) for measured results, reproduction and limitations.

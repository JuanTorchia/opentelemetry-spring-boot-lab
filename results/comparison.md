# OpenTelemetry Spring Boot Lab - Comparison

Generated: 2026-05-16T02:35:37

## Environment

- Mode: editorial
- Dataset: editorial
- Runs: 3
- Requests per scenario per run: 200
- Warmup requests per scenario: 20
- Requested concurrency: 8
- Backend: Spring Boot 3, Java 21 target, PostgreSQL 16, Jaeger all-in-one

## Summary

| scenario | avg_ms | p95_ms | spans_avg | db_spans_avg | downstream_spans_avg | error_spans_total | error_spans_avg | interpretation |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| baseline | 49 | 96 | 3.06 | 1.06 | 0 | 0 | 0 | Logs confirm OK; trace shows a compact request with limited DB work. |
| downstream-slow | 353 | 402 | 4 | 0 | 3 | 0 | 0 | Time is dominated by HTTP/downstream, not Postgres. |
| mixed | 365 | 399 | 7.61 | 1.61 | 2 | 0 | 0 | Trace splits DB, downstream and transform time; logs are less explanatory. |
| n-plus-one | 190 | 408 | 63.52 | 61.52 | 0 | 0 | 0 | Trace exposes DB fan-out: many DB spans for one business request. |
| optimized | 39 | 73 | 3.07 | 1.07 | 0 | 0 | 0 | Same business shape with fewer DB spans after join/aggregation. |
| partial-error | 157 | 190 | 6.32 | 1.32 | 2 | 1800 | 3 | Trace marks controlled downstream error and logs carry traceId/spanId. |

## What traces showed that logs did not make obvious

- N+1 appears as DB span fan-out inside one request, without enabling noisy SQL logs.
- The downstream scenario isolates HTTP wait time from local DB time.
- The mixed scenario separates DB, downstream and transformation spans, which makes flat request logs less ambiguous.
- The partial error keeps the request controlled while marking the downstream failure in the trace and correlating logs via traceId/spanId.
- In partial-error, rror_spans_total is a total across all measured requests; use rror_spans_avg for per-request reading.

## What this lab does not prove

- It does not measure production overhead.
- It does not prove Jaeger is mandatory; Jaeger is used because it is simple for a local lab.
- It does not claim traces replace logs.
- It does not claim tracing fixes performance; it makes the shape of latency visible.

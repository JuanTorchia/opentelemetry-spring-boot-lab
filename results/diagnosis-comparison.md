# Logs vs Traces - Diagnosis Comparison

Generated: 2026-05-16T03:10:09

This table compares available diagnostic signals. It does not declare a universal winner and does not measure production overhead.

| scenario | logs_available_signal | trace_available_signal | likely_root_cause_from_logs | likely_root_cause_from_trace | diagnosis_confidence_logs | diagnosis_confidence_trace | dominant_span_type | dominant_span_duration_ms | duration_denominator_type | dominant_span_duration_vs_root_pct | db_cumulative_span_duration_vs_root_pct | downstream_cumulative_span_duration_vs_root_pct | editorial_takeaway |
|---|---|---|---|---|---|---|---|---:|---|---:|---:|---:|---|
| baseline | status OK; duracion total baja; traceId/spanId para correlacion | pocos spans; una consulta DB compacta; sin error | request saludable; sin causa raiz que investigar | request saludable; DB acotada | high | high | business | 8.38 | root_span | 65.49 | 56.64 | 0 | El trace confirma la forma simple esperada; no todos los casos necesitan una narrativa compleja. |
| optimized | status OK; duracion total baja; resultado de negocio correcto | pocos DB spans; agregacion visible | probablemente saludable; no prueba por si solo que no haya fan-out interno | consulta agregada sin fan-out DB relevante | medium | high | business | 3.27 | root_span | 43.14 | 33.4 | 0 | La comparacion con N+1 es fuerte porque el trace muestra menos spans para el mismo shape funcional. |
| n-plus-one | status OK; duracion total elevada o ruidosa; traceId/spanId para buscar el caso | muchos DB spans dentro de una sola request; fan-out visible | ambiguo; requiere SQL logs, inspeccion extra o conocimiento previo del codigo | DB fan-out / N+1 | low | high | business | 85.12 | root_span | 93.06 | 87.84 | 0 | Sin SQL debug, los logs sugieren lentitud; el trace muestra la forma repetitiva de la causa. |
| downstream-slow | status OK; duracion total cercana al delay configurado | tiempo concentrado en spans HTTP/downstream | posible espera externa; DB y transformacion quedan poco separadas | downstream lento domina la request | medium | high | downstream | 321.44 | root_span | 100 | 0 | 294.53 | El trace separa espera externa de trabajo local sin convertir los logs en HTTP debug. |
| mixed | status OK; duracion total alta; eventos de negocio por escenario | spans DB, downstream y transformacion ordenados temporalmente | ambiguo; varias etapas plausibles compiten como causa dominante | distribucion causal entre DB, downstream y transformacion | low | high | downstream | 317.64 | root_span | 93.22 | 4.79 | 183.95 | El caso mixto muestra mejor que los traces aportan estructura causal, no magia. |
| partial-error | error controlado con status parcial; traceId/spanId; tipo de excepcion | spans marcados con error dentro de una request parcialmente exitosa | fallo downstream controlado; cuesta ver su posicion causal exacta | downstream fallo dentro de una request que responde parcialmente | medium | high | downstream | 116.59 | root_span | 89.18 | 5.66 | 172.66 | Logs y traces se complementan: el log avisa, el trace ubica el error en la jerarquia. |

## Metric notes

- `diagnosis_confidence_*` is an editorial classification based on available signals, not an automatically measured metric.
- `dominant_span_type`, `dominant_span_duration_ms`, `duration_denominator_type`, `dominant_span_duration_vs_root_pct`, `db_cumulative_span_duration_vs_root_pct` and `downstream_cumulative_span_duration_vs_root_pct` are derived from Jaeger span durations exported during the run.
- `duration_denominator_type` records how the denominator was selected: `root_span` when Jaeger references identify one clear root, `http_request_span` when the HTTP request span is used, or `largest_observed_span` when the trace is ambiguous.
- The `*_vs_root_pct` values are cumulative diagnostic signals from exported spans, not production overhead measurements and not exclusive wall-clock distribution.
- Cumulative values can exceed 100% when spans are nested, duplicated as client/server pairs, or overlap. Use them as diagnostic hints, not exact time allocation.
- Logs in this lab include `traceId`, `spanId`, scenario, status and total request duration, but they do not print SQL debug or reveal root causes artificially.

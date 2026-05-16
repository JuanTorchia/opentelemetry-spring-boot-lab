# Brief editorial

## Tesis principal

Los logs te dicen que paso. Los traces te muestran donde se fue el tiempo. OpenTelemetry no sirve para decorar dashboards: sirve para explicar una request lenta cuando hay DB, downstream, errores y N+1 mezclados.

Version sobria para publicar: logs y traces se complementan. El `traceId` y el `spanId` conectan ambos mundos. Un trace no arregla un N+1, lo hace visible.

## Hallazgos defendibles

- El escenario N+1 genera mas spans DB que el optimizado para el mismo resultado de negocio.
- El escenario downstream lento concentra duracion en HTTP/downstream, no en Postgres.
- El escenario mixto muestra una distribucion por etapas que no aparece en logs planos.
- El error parcial queda marcado en el trace y se puede correlacionar con logs por `traceId`/`spanId`.
- La auto-instrumentacion reduce trabajo accidental, pero los spans manuales siguen siendo utiles para explicar negocio.

## Hallazgos que NO debemos afirmar

- No afirmar que OpenTelemetry reemplaza logs.
- No afirmar que los logs no sirven.
- No afirmar que Jaeger o Tempo son obligatorios.
- No afirmar que el overhead observado aplica a produccion.
- No afirmar que tracing arregla performance.
- No afirmar que con traces ya hay observabilidad completa.

## Criticas esperables de observabilidad

- "Esto no mide overhead." Respuesta: correcto; el lab no esta disenado para overhead sino para capacidad explicativa.
- "Jaeger no es la unica opcion." Respuesta: correcto; se eligio por simplicidad reproducible local.
- "Un N+1 tambien se ve con SQL logs." Respuesta: si, pero con logging mas invasivo y peor relacion senal/ruido para una request concreta.
- "Demasiados spans tambien confunden." Respuesta: de acuerdo; el brief debe mostrar que OTel mal instrumentado puede generar ruido.
- "Esto no cubre metricas." Respuesta: correcto; el post habla de logs + traces, no de observabilidad completa.

## Como responderlas

Responder con precision: el experimento no prueba superioridad universal de tracing. Prueba que, para requests donde DB, downstream y errores se mezclan, un trace bien instrumentado reduce ambiguedad operativa.

## Frases prohibidas

- "OpenTelemetry reemplaza logs"
- "los logs no sirven"
- "Jaeger/Tempo es obligatorio"
- "este overhead aplica a produccion"
- "tracing arregla performance"
- "con traces ya tenes observabilidad completa"

## Titulos recomendados ES

- OpenTelemetry en Spring Boot 3: cuando los logs dicen OK pero el trace muestra el problema
- Logs, traces y una request lenta: un laboratorio reproducible con Spring Boot 3
- El N+1 que los logs no explicaban: evidencia con OpenTelemetry, Postgres y Jaeger

## Recommended titles EN

- OpenTelemetry in Spring Boot 3: when logs say OK but traces show the latency
- Logs, traces, and a slow request: a reproducible Spring Boot 3 lab
- The N+1 logs did not explain: evidence with OpenTelemetry, Postgres, and Jaeger

## Tabla de resultados principales

Corrida editorial local: `2026-05-16T00:00:34`, dataset `editorial`, 3 runs, 200 requests por escenario por run, concurrencia 8.

| scenario | avg_ms | p95_ms | spans_avg | db_spans_avg | downstream_spans_avg | error_spans |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 86 | 120 | 3.05 | 1.05 | 0 | 0 |
| downstream-slow | 351 | 398 | 4 | 0 | 3 | 0 |
| mixed | 370 | 417 | 7.54 | 1.54 | 2 | 0 |
| n-plus-one | 137 | 247 | 63.27 | 61.27 | 0 | 0 |
| optimized | 40 | 79 | 3.06 | 1.06 | 0 | 0 |
| partial-error | 176 | 237 | 6.28 | 1.28 | 2 | 1800 |

El p99 de `baseline` tuvo un outlier local alto en esta corrida. Usarlo como advertencia metodologica, no como hallazgo editorial.

## Repo, commit y tag final

- Repo: `https://github.com/JuanTorchia/opentelemetry-spring-boot-lab`
- Commit: usar `git rev-parse editorial-final` para resolver el commit exacto del tag publicado.
- Tag: `editorial-final`

## Limitaciones

- Lab local, no benchmark de produccion.
- Downstream simulado dentro de la misma app para simplificar reproducibilidad.
- PowerShell runner suficiente para evidencia editorial, no equivalente a k6/JMeter.
- Resultados dependen del hardware local, estado de Docker Desktop y JVM.
- Los SVGs son assets reproducibles; para mostrar UI de Jaeger conviene capturar screenshots reales desde `http://localhost:16686`.
- Los archivos `results/assets/jaeger-*.png` son capturas reales de Jaeger tomadas desde traces generados por el lab.
- Los archivos `results/assets/trace-*.svg` son assets sinteticos reproducibles; usarlos como apoyo visual, no como evidencia de UI.
- En `partial-error`, `error_span_count` / `error_spans_total` es total acumulado de la corrida. Para lectura por request usar `error_spans_avg`.

## Que cambiar del draft original

- Cambiar de tutorial basico a narrativa experimental.
- Abrir con una request que parece "OK" en logs pero se divide mal en el trace.
- Mostrar N+1 vs optimizado como comparacion, no como afirmacion abstracta.
- Incluir error parcial para demostrar correlacion `traceId`/`spanId`.
- Agregar una seccion de limites para no sobreactuar conclusiones.

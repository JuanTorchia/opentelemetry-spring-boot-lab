# Brief editorial

## Tesis principal

Los logs te dicen que paso. Los traces te muestran donde se fue el tiempo. OpenTelemetry no sirve para decorar dashboards: sirve para explicar una request lenta cuando hay DB, downstream, errores y N+1 mezclados.

Version sobria para publicar: logs y traces se complementan. El `traceId` y el `spanId` conectan ambos mundos. Un trace no arregla un N+1, lo hace visible.

Tesis final del lab: OpenTelemetry no mejora la performance por si mismo. Mejora la capacidad de diagnosticar por que una request fue lenta, ruidosa o parcialmente fallida. Logs y traces se complementan, pero el trace hace visible la forma causal de la request.

## Hallazgos defendibles

- El escenario N+1 genera mas spans DB que el optimizado para el mismo resultado de negocio.
- El escenario downstream lento concentra duracion en HTTP/downstream, no en Postgres.
- El escenario mixto muestra una distribucion por etapas que no aparece en logs planos.
- El error parcial queda marcado en el trace y se puede correlacionar con logs por `traceId`/`spanId`.
- La auto-instrumentacion reduce trabajo accidental, pero los spans manuales siguen siendo utiles para explicar negocio.

## Logs vs traces: comparacion de diagnostico

Los logs del lab muestran eventos de aplicacion, `traceId`, `spanId`, escenario, status y duracion total de la request. Son buenos logs operativos: permiten buscar un caso, saber si termino OK o parcialmente fallido, y correlacionarlo con una traza.

Los traces muestran estructura causal: spans HTTP, DB, downstream, transformacion, errores, fan-out y duracion por etapa. La comparacion no busca declarar un ganador universal. Busca mostrar que senales estan disponibles usando solo logs planos y que senales aparecen cuando se mira la traza de la misma request.

La tabla generada en `results/diagnosis-comparison.md` es la fuente para esta comparacion. Usa los mismos escenarios de la corrida editorial y agrega senales derivadas de Jaeger cuando estan disponibles: `dominant_span_type`, `dominant_span_duration_ms`, `duration_denominator_type`, `dominant_span_duration_vs_root_pct`, `db_cumulative_span_duration_vs_root_pct` y `downstream_cumulative_span_duration_vs_root_pct`. Esas metricas ayudan a diagnosticar, pero no miden overhead productivo.

`diagnosis_confidence_*` es una clasificacion editorial basada en senales disponibles, no una metrica medida automaticamente. Usarla para narrar cuanta ambiguedad queda con cada fuente, no como benchmark.

Las metricas `*_vs_root_pct` son porcentajes acumulados de duracion de spans exportados por Jaeger. El denominador se registra en `duration_denominator_type`: `root_span` si las referencias de Jaeger identifican un root unico, `http_request_span` si se usa el span HTTP principal, o `largest_observed_span` si la traza queda ambigua. No son overhead, no son porcentaje exclusivo del tiempo real de la request, y pueden superar 100% cuando hay spans anidados, pares cliente/servidor o solapamiento. Sirven como senal diagnostica, no como medicion exacta de distribucion de tiempo.

## Que se puede diagnosticar con logs

- Status de la request.
- Duracion total.
- Errores explicitos.
- Correlacion por `traceId`/`spanId`.
- Eventos de negocio relevantes.

## Que cuesta diagnosticar solo con logs

- Fan-out DB por request sin SQL debug.
- Distribucion interna del tiempo.
- Que etapa domino la latencia.
- Errores parciales dentro de una request exitosa.
- Causalidad entre DB, downstream y transformacion.

## Que aporta el trace

- Estructura temporal.
- Jerarquia de spans.
- Fan-out visible.
- Duracion por etapa.
- Errores marcados cerca de su causa.
- Correlacion con logs.

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
- "Con buenos logs tambien puedo diagnosticar downstream lento." Respuesta: a veces si. El punto del lab no es negar buenos logs, sino mostrar que el trace separa visualmente tiempo local, downstream y DB sin convertir cada request en logging de bajo nivel.
- "Si instrumentas mal, los traces son ruido." Respuesta: correcto. El post debe decirlo. Demasiados spans o spans mal nombrados pueden esconder el problema.
- "El trace no reemplaza metricas." Respuesta: correcto. El trace explica una request concreta; las metricas dicen frecuencia, tendencia e impacto agregado.
- "Jaeger local no representa produccion." Respuesta: correcto. Jaeger local es una herramienta reproducible para el experimento, no una recomendacion obligatoria de plataforma.
- "El experimento esta sesgado porque ya sabes los escenarios." Respuesta: correcto parcialmente. La ventaja es que permite comparar senales contra una causa conocida. No prueba que una persona siempre diagnostique mas rapido; prueba que cierta informacion esta o no esta disponible en cada enfoque.

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

Corrida editorial local: `2026-05-16T03:10:09`, dataset `editorial`, 3 runs, 200 requests por escenario por run, concurrencia 8.

| scenario | avg_ms | p95_ms | spans_avg | db_spans_avg | downstream_spans_avg | error_spans_total | error_spans_avg |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline | 36 | 55 | 3.04 | 1.04 | 0 | 0 | 0 |
| downstream-slow | 342 | 374 | 4 | 0 | 3 | 0 | 0 |
| mixed | 362 | 395 | 7.57 | 1.57 | 2 | 0 | 0 |
| n-plus-one | 119 | 209 | 63.38 | 61.38 | 0 | 0 | 0 |
| optimized | 33 | 59 | 3.04 | 1.04 | 0 | 0 | 0 |
| partial-error | 153 | 184 | 6.27 | 1.27 | 2 | 1800 | 3 |

Los percentiles altos pueden moverse por ruido local de Docker/JVM. Usarlos como contexto metodologico, no como hallazgo editorial aislado.
En `partial-error`, `error_spans_total` es el acumulado de toda la corrida. Para narrar el post conviene usar `error_spans_avg`, que expresa la lectura por request.

## Repo, commit y tag final

- Repo: `https://github.com/JuanTorchia/opentelemetry-spring-boot-lab`
- Commit: resolver con `git rev-parse editorial-final-diagnosis-comparison-v2`
- Tag: `editorial-final-diagnosis-comparison-v2`

## Limitaciones

- Lab local, no benchmark de produccion.
- Downstream simulado dentro de la misma app para simplificar reproducibilidad.
- PowerShell runner suficiente para evidencia editorial, no equivalente a k6/JMeter.
- Resultados dependen del hardware local, estado de Docker Desktop y JVM.
- Los SVGs son assets reproducibles; para mostrar UI de Jaeger conviene capturar screenshots reales desde `http://localhost:16686`.
- Los archivos `results/assets/jaeger-*.png` son capturas reales de Jaeger tomadas desde traces generados por el lab.
- Los archivos `results/assets/trace-*.svg` son assets sinteticos reproducibles; usarlos como apoyo visual, no como evidencia de UI.
- En `partial-error`, `error_spans_total` es total acumulado de la corrida. Para lectura por request usar `error_spans_avg`.
- `results/diagnosis-comparison.md` compara senales disponibles para diagnostico con logs planos y con traces. No debe presentarse como prueba de que traces siempre son mejores.

## Que cambiar del draft original

- Cambiar de tutorial basico a narrativa experimental.
- Abrir con una request que parece "OK" en logs pero se divide mal en el trace.
- Mostrar N+1 vs optimizado como comparacion, no como afirmacion abstracta.
- Incluir error parcial para demostrar correlacion `traceId`/`spanId`.
- Agregar una seccion de limites para no sobreactuar conclusiones.

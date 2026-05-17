# OpenTelemetry Spring Boot Lab

Laboratorio reproducible para convertir una tesis editorial sobre logs y traces en evidencia ejecutable.

Articulo relacionado / Related article:

- Español: [OpenTelemetry en Spring Boot 3: cuando el log dice OK y el trace muestra el problema](https://juanchi.dev/es/blog/opentelemetry-spring-boot-logs-vs-traces-diagnostico)
- English: [OpenTelemetry on Spring Boot 3: when logs say OK and traces show the problem](https://juanchi.dev/en/blog/opentelemetry-spring-boot-logs-vs-traces-diagnosis)

Tesis: los logs dicen que paso; los traces muestran donde se fue el tiempo. OpenTelemetry no decora dashboards: ayuda a explicar una request lenta cuando DB, downstream, pool, errores y N+1 aparecen mezclados.

Tag recomendado para citar el experimento: `editorial-final-diagnosis-comparison-v2`.

## Stack

- Spring Boot 3
- Java 21 target
- Maven
- PostgreSQL 16
- Docker Compose
- OpenTelemetry Java Agent + spans manuales
- Jaeger all-in-one
- PowerShell runner para Windows
- Bash wrapper si existe `pwsh`

## Por que Java Agent + spans manuales

El Java Agent captura automaticamente HTTP server, HTTP client y JDBC sin ensuciar el codigo del lab con wrappers artificiales. Los spans manuales se usan solo para etapas de negocio: carga N+1, query optimizada, llamada downstream, transformacion y error parcial. Esa mezcla es mas honesta para el post: auto-instrumentacion para infraestructura, spans manuales para explicar intencion.

Jaeger se eligio por simplicidad local: una imagen, UI web, API para consultar traces por `traceId`. Tempo tambien seria defendible, pero requiere mas piezas para una demo editorial local.

## Que mide

Escenarios:

- `baseline`: consulta agregada simple a Postgres.
- `n-plus-one`: lista tareas y consulta comentarios por cada item.
- `optimized`: devuelve el mismo shape con join/agregacion.
- `downstream-slow`: llama a un downstream local con delay configurable.
- `mixed`: combina DB, downstream y transformacion en memoria.
- `partial-error`: DB OK + downstream con 500 controlado.

Datasets:

- `small`: 1k tasks.
- `editorial`: 50k tasks.

Tablas sinteticas:

- `organizations`
- `users`
- `projects`
- `tasks`
- `comments`

No hay datos personales reales.

## Correr smoke

```powershell
.\scripts\run-lab.ps1 -Mode smoke -Size small
```

Esto levanta Docker Compose, descarga el OpenTelemetry Java Agent en `tools/`, empaqueta la app si falta el jar, seedea Postgres, ejecuta escenarios y genera resultados. El runner usa la app en `http://localhost:18080` y Postgres publicado en `localhost:65432` para evitar conflictos habituales con servicios locales.

## Correr editorial

```powershell
.\scripts\run-lab.ps1 -Mode editorial -Size editorial -Runs 3 -Requests 200 -Warmup 20 -Concurrency 8
```

Esta es la matriz editorial principal. Ejecuta `baseline`, `optimized`, `n-plus-one`, `downstream-slow`, `mixed` y `partial-error` contra el dataset de 50k tasks, consulta Jaeger por `traceId` y regenera los reportes comparativos.

Bash, si tenes `pwsh` instalado:

```bash
bash scripts/run-lab.sh --mode smoke --size small
bash scripts/run-lab.sh --mode editorial --size editorial --runs 3 --requests 200 --warmup 20 --concurrency 8
```

## Abrir Jaeger

```text
http://localhost:16686
```

Servicio:

```text
otel-spring-boot-lab
```

Buscar operaciones `/lab/n-plus-one`, `/lab/optimized`, `/lab/downstream-slow`, `/lab/mixed` o `/lab/partial-error`.

Cada respuesta HTTP incluye:

- `X-Trace-Id`
- `X-Span-Id`

Los logs tambien imprimen `traceId` y `spanId`, por lo que se puede saltar de una linea de log al trace correspondiente.

## Interpretar traces

- En `baseline`, deberias ver pocos spans y una consulta DB compacta.
- En `n-plus-one`, deberias ver fan-out de spans DB.
- En `optimized`, deberias ver menos spans DB para el mismo resultado de negocio.
- En `downstream-slow`, la duracion se concentra en HTTP client/server del downstream, no en DB.
- En `mixed`, la distribucion por spans separa DB, downstream y transformacion.
- En `partial-error`, el trace marca error en el tramo downstream y los logs tienen el mismo traceId.

## Resultados

El runner regenera:

- `results/comparison.csv`
- `results/comparison.md`
- `results/diagnosis-comparison.csv`
- `results/diagnosis-comparison.md`
- `results/assets/trace-n-plus-one.svg`
- `results/assets/trace-optimized.svg`
- `results/assets/trace-downstream-slow.svg`
- `results/assets/span-count-by-scenario.svg`
- `results/assets/p95-by-scenario.svg`
- `results/assets/jaeger-n-plus-one.png`
- `results/assets/jaeger-optimized.png`
- `results/assets/jaeger-downstream-slow.png`
- `results/assets/jaeger-partial-error.png`

Los raw results quedan en `results/raw/` y estan ignorados por Git para no versionar archivos pesados.

`results/comparison.md` resume latencia, conteos de spans y errores por escenario. `results/diagnosis-comparison.md` compara que puede inferirse con logs planos frente a que aparece en traces: senales disponibles, causa probable, confianza diagnostica editorial y metricas derivadas de spans como `dominant_span_type`, `duration_denominator_type`, `db_cumulative_span_duration_vs_root_pct` y `downstream_cumulative_span_duration_vs_root_pct`.

Las metricas `*_vs_root_pct` son porcentajes acumulados de duracion de spans exportados por Jaeger contra el denominador registrado en `duration_denominator_type`. No son overhead, no son distribucion exclusiva del tiempo real de la request y pueden superar 100% cuando hay spans anidados, pares cliente/servidor o solapamiento. Sirven como senal diagnostica, no como medicion exacta de asignacion de tiempo.

Los logs son intencionalmente utiles pero no tramposos: incluyen `traceId`, `spanId`, escenario, status y duracion total, pero no imprimen SQL debug ni dicen artificialmente que un escenario es N+1.

## Regenerar assets

Los assets se regeneran como parte del runner. Para capturas reales de Jaeger:

1. Corre el lab.
2. Abri `http://localhost:16686`.
3. Filtra por servicio `otel-spring-boot-lab`.
4. Abri un trace por escenario.
5. Guarda screenshot junto a los SVGs en `results/assets/`.

Los SVGs incluidos sirven como assets editoriales reproducibles, no como reemplazo de screenshots de Jaeger cuando se quiera mostrar la UI real. Las PNG `jaeger-*.png` son capturas reales de Jaeger tomadas desde traces generados por este lab.

## Validaciones

```powershell
mvn test
mvn package
docker compose config --quiet
.\scripts\run-lab.ps1 -Mode smoke -Size small
.\scripts\run-lab.ps1 -Mode editorial -Size editorial -Runs 3 -Requests 200 -Warmup 20 -Concurrency 8
```

## Limpieza Docker

```powershell
docker compose down
docker compose down -v
```

Usa `down -v` solo si queres borrar el volumen local de Postgres.

## Limitaciones

- No mide overhead de produccion.
- No compara proveedores de tracing.
- No demuestra que Jaeger sea obligatorio.
- No reemplaza profiling ni metricas.
- La carga se genera desde PowerShell; sirve para evidencia editorial local, no para benchmark riguroso.
- El downstream esta en la misma app para mantener el lab compacto; eso reduce realismo de red pero mantiene reproducibilidad.

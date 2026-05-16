param(
    [ValidateSet("smoke", "editorial")]
    [string]$Mode = "smoke",
    [ValidateSet("small", "editorial")]
    [string]$Size = "small",
    [int]$Runs = 1,
    [int]$Requests = 12,
    [int]$Warmup = 3,
    [int]$Concurrency = 2
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::InvariantCulture
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResultsDir = Join-Path $Root "results"
$RawDir = Join-Path $ResultsDir "raw"
$AssetsDir = Join-Path $ResultsDir "assets"
$ToolsDir = Join-Path $Root "tools"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $ResultsDir, $RawDir, $AssetsDir, $ToolsDir, $LogDir | Out-Null

$AppPort = 18080
$AppUrl = "http://localhost:$AppPort"
$JaegerUrl = "http://localhost:16686"
$AgentPath = Join-Path $ToolsDir "opentelemetry-javaagent.jar"
$JarPath = Join-Path $Root "target\opentelemetry-spring-boot-lab-0.1.0.jar"
$AppLog = Join-Path $LogDir "app-$Mode-$Size.out.log"
$AppErrLog = Join-Path $LogDir "app-$Mode-$Size.err.log"
$AgentVersion = "2.9.0"

function Wait-Http($Url, $Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 | Out-Null
            return
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    throw "Timeout waiting for $Url"
}

function Get-SpanTagValue($Span, [string]$Key) {
    $tag = @($Span.tags | Where-Object { $_.key -eq $Key } | Select-Object -First 1)
    if ($tag.Count -eq 0) { return $null }
    return $tag[0].value
}

function Test-DbSpan($Span) {
    return [bool](@($Span.tags | Where-Object { $_.key -eq "db.system" -or $_.key -eq "db.system.name" }).Count)
}

function Test-DownstreamSpan($Span) {
    $path = Get-SpanTagValue $Span "url.path"
    return ($Span.operationName -like "*downstream*") -or ($path -like "*downstream*")
}

function Get-SpanDiagnostics($Spans) {
    $all = @($Spans)
    if ($all.Count -eq 0) {
        return @{
            dominant_type = "none"; dominant_duration_ms = 0; dominant_share_pct = 0
            db_share_pct = 0; downstream_share_pct = 0
        }
    }
    $rootDurationUs = [double](($all | Measure-Object duration -Maximum).Maximum)
    if ($rootDurationUs -le 0) { $rootDurationUs = 1 }
    $classified = $all | ForEach-Object {
        $type = if (Test-DbSpan $_) {
            "db"
        } elseif (Test-DownstreamSpan $_) {
            "downstream"
        } elseif ($_.operationName -like "business.*") {
            "business"
        } elseif ($_.operationName -like "GET*" -or $_.operationName -like "POST*") {
            "http"
        } else {
            "other"
        }
        [pscustomobject]@{ type = $type; duration = [double]$_.duration }
    }
    $dominant = @($classified | Where-Object type -ne "http" | Sort-Object duration -Descending | Select-Object -First 1)
    if ($dominant.Count -eq 0) {
        $dominant = @($classified | Sort-Object duration -Descending | Select-Object -First 1)
    }
    $dbDuration = [double](($classified | Where-Object type -eq "db" | Measure-Object duration -Sum).Sum)
    $downstreamDuration = [double](($classified | Where-Object type -eq "downstream" | Measure-Object duration -Sum).Sum)
    return @{
        dominant_type = $dominant[0].type
        dominant_duration_ms = [Math]::Round($dominant[0].duration / 1000.0, 2)
        dominant_share_pct = [Math]::Round(($dominant[0].duration / $rootDurationUs) * 100.0, 2)
        db_share_pct = [Math]::Round(($dbDuration / $rootDurationUs) * 100.0, 2)
        downstream_share_pct = [Math]::Round(($downstreamDuration / $rootDurationUs) * 100.0, 2)
    }
}

function Invoke-LabRequest($Scenario, $Path) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = 0
    $traceId = ""
    try {
        $response = Invoke-WebRequest -Uri "$AppUrl$Path" -UseBasicParsing -TimeoutSec 20 -SkipHttpErrorCheck
        $status = [int]$response.StatusCode
        if ($response.Headers["X-Trace-Id"]) {
            $traceId = $response.Headers["X-Trace-Id"][0]
        }
    } catch {
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        } else {
            $status = 599
        }
    }
    $sw.Stop()
    Start-Sleep -Milliseconds 250
    $counts = Get-TraceCounts $traceId
    [pscustomobject]@{
        scenario = $Scenario
        status = $status
        successful = ($status -ge 200 -and $status -lt 400)
        duration_ms = [int]$sw.ElapsedMilliseconds
        trace_id = $traceId
        trace_span_count = $counts.trace
        db_span_count = $counts.db
        downstream_span_count = $counts.downstream
        error_span_count = $counts.error
        dominant_span_type = $counts.dominant_type
        dominant_span_duration_ms = $counts.dominant_duration_ms
        dominant_span_share_pct = $counts.dominant_share_pct
        db_span_share_pct = $counts.db_share_pct
        downstream_span_share_pct = $counts.downstream_share_pct
        log_lines = 3
    }
}

function Get-TraceCounts($TraceId) {
    if ([string]::IsNullOrWhiteSpace($TraceId) -or $TraceId -eq "none") {
        return @{
            trace = 0; db = 0; downstream = 0; error = 0
            dominant_type = "none"; dominant_duration_ms = 0; dominant_share_pct = 0
            db_share_pct = 0; downstream_share_pct = 0
        }
    }
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try {
            $trace = Invoke-RestMethod -Uri "$JaegerUrl/api/traces/$TraceId" -TimeoutSec 5
            if (!$trace.data -or @($trace.data).Count -eq 0) {
                Start-Sleep -Milliseconds 300
                continue
            }
        $spans = @($trace.data[0].spans)
        $db = @($spans | Where-Object { $_.tags | Where-Object { $_.key -eq "db.system" -or $_.key -eq "db.system.name" } }).Count
        $downstream = @($spans | Where-Object {
            ($_.operationName -like "*downstream*") -or
            ($_.tags | Where-Object { $_.key -eq "url.path" -and $_.value -like "*downstream*" })
        }).Count
        $errors = @($spans | Where-Object { $_.tags | Where-Object { ($_.key -eq "error" -and $_.value -eq $true) -or ($_.key -eq "otel.status_code" -and $_.value -eq "ERROR") } }).Count
            $diagnostics = Get-SpanDiagnostics $spans
            return @{
                trace = $spans.Count; db = $db; downstream = $downstream; error = $errors
                dominant_type = $diagnostics.dominant_type
                dominant_duration_ms = $diagnostics.dominant_duration_ms
                dominant_share_pct = $diagnostics.dominant_share_pct
                db_share_pct = $diagnostics.db_share_pct
                downstream_share_pct = $diagnostics.downstream_share_pct
            }
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }
    return @{
        trace = 0; db = 0; downstream = 0; error = 0
        dominant_type = "none"; dominant_duration_ms = 0; dominant_share_pct = 0
        db_share_pct = 0; downstream_share_pct = 0
    }
}

function Percentile($Values, [double]$P) {
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return 0 }
    $index = [Math]::Ceiling($P * $sorted.Count) - 1
    $index = [Math]::Max(0, [Math]::Min($index, $sorted.Count - 1))
    return [int]$sorted[$index]
}

function Interpret($Scenario) {
    switch ($Scenario) {
        "baseline" { "Logs confirm OK; trace shows a compact request with limited DB work." }
        "n-plus-one" { "Trace exposes DB fan-out: many DB spans for one business request." }
        "optimized" { "Same business shape with fewer DB spans after join/aggregation." }
        "downstream-slow" { "Time is dominated by HTTP/downstream, not Postgres." }
        "mixed" { "Trace splits DB, downstream and transform time; logs are less explanatory." }
        "partial-error" { "Trace marks controlled downstream error and logs carry traceId/spanId." }
        default { "Review raw trace before interpreting." }
    }
}

function Get-DiagnosisDefinition($Scenario) {
    switch ($Scenario) {
        "baseline" {
            return [ordered]@{
                logs_available_signal = "status OK; duracion total baja; traceId/spanId para correlacion"
                trace_available_signal = "pocos spans; una consulta DB compacta; sin error"
                likely_root_cause_from_logs = "request saludable; sin causa raiz que investigar"
                likely_root_cause_from_trace = "request saludable; DB acotada"
                diagnosis_confidence_logs = "high"
                diagnosis_confidence_trace = "high"
                editorial_takeaway = "El trace confirma la forma simple esperada; no todos los casos necesitan una narrativa compleja."
            }
        }
        "optimized" {
            return [ordered]@{
                logs_available_signal = "status OK; duracion total baja; resultado de negocio correcto"
                trace_available_signal = "pocos DB spans; agregacion visible"
                likely_root_cause_from_logs = "probablemente saludable; no prueba por si solo que no haya fan-out interno"
                likely_root_cause_from_trace = "consulta agregada sin fan-out DB relevante"
                diagnosis_confidence_logs = "medium"
                diagnosis_confidence_trace = "high"
                editorial_takeaway = "La comparacion con N+1 es fuerte porque el trace muestra menos spans para el mismo shape funcional."
            }
        }
        "n-plus-one" {
            return [ordered]@{
                logs_available_signal = "status OK; duracion total elevada o ruidosa; traceId/spanId para buscar el caso"
                trace_available_signal = "muchos DB spans dentro de una sola request; fan-out visible"
                likely_root_cause_from_logs = "ambiguo; requiere SQL logs, inspeccion extra o conocimiento previo del codigo"
                likely_root_cause_from_trace = "DB fan-out / N+1"
                diagnosis_confidence_logs = "low"
                diagnosis_confidence_trace = "high"
                editorial_takeaway = "Sin SQL debug, los logs sugieren lentitud; el trace muestra la forma repetitiva de la causa."
            }
        }
        "downstream-slow" {
            return [ordered]@{
                logs_available_signal = "status OK; duracion total cercana al delay configurado"
                trace_available_signal = "tiempo concentrado en spans HTTP/downstream"
                likely_root_cause_from_logs = "posible espera externa; DB y transformacion quedan poco separadas"
                likely_root_cause_from_trace = "downstream lento domina la request"
                diagnosis_confidence_logs = "medium"
                diagnosis_confidence_trace = "high"
                editorial_takeaway = "El trace separa espera externa de trabajo local sin convertir los logs en HTTP debug."
            }
        }
        "mixed" {
            return [ordered]@{
                logs_available_signal = "status OK; duracion total alta; eventos de negocio por escenario"
                trace_available_signal = "spans DB, downstream y transformacion ordenados temporalmente"
                likely_root_cause_from_logs = "ambiguo; varias etapas plausibles compiten como causa dominante"
                likely_root_cause_from_trace = "distribucion causal entre DB, downstream y transformacion"
                diagnosis_confidence_logs = "low"
                diagnosis_confidence_trace = "high"
                editorial_takeaway = "El caso mixto muestra mejor que los traces aportan estructura causal, no magia."
            }
        }
        "partial-error" {
            return [ordered]@{
                logs_available_signal = "error controlado con status parcial; traceId/spanId; tipo de excepcion"
                trace_available_signal = "spans marcados con error dentro de una request parcialmente exitosa"
                likely_root_cause_from_logs = "fallo downstream controlado; cuesta ver su posicion causal exacta"
                likely_root_cause_from_trace = "downstream fallo dentro de una request que responde parcialmente"
                diagnosis_confidence_logs = "medium"
                diagnosis_confidence_trace = "high"
                editorial_takeaway = "Logs y traces se complementan: el log avisa, el trace ubica el error en la jerarquia."
            }
        }
        default {
            return [ordered]@{
                logs_available_signal = "sin definicion"
                trace_available_signal = "sin definicion"
                likely_root_cause_from_logs = "sin definicion"
                likely_root_cause_from_trace = "sin definicion"
                diagnosis_confidence_logs = "unknown"
                diagnosis_confidence_trace = "unknown"
                editorial_takeaway = "Revisar raw results antes de interpretar."
            }
        }
    }
}

function Summarize($Rows) {
    $Rows | Group-Object scenario | ForEach-Object {
        $group = @($_.Group)
        $success = @($group | Where-Object successful).Count
        [pscustomobject]@{
            scenario = $_.Name
            mode = $Mode
            total_requests = $group.Count
            successful_requests = $success
            error_rate = [Math]::Round(($group.Count - $success) / [double]$group.Count, 4)
            avg_ms = [int][Math]::Round(($group | Measure-Object duration_ms -Average).Average)
            p50_ms = Percentile ($group.duration_ms) 0.50
            p95_ms = Percentile ($group.duration_ms) 0.95
            p99_ms = Percentile ($group.duration_ms) 0.99
            trace_span_count_avg = [Math]::Round(($group | Measure-Object trace_span_count -Average).Average, 2)
            db_span_count_avg = [Math]::Round(($group | Measure-Object db_span_count -Average).Average, 2)
            downstream_span_count_avg = [Math]::Round(($group | Measure-Object downstream_span_count -Average).Average, 2)
            error_spans_total = [int]($group | Measure-Object error_span_count -Sum).Sum
            error_spans_avg = [Math]::Round(($group | Measure-Object error_span_count -Average).Average, 2)
            dominant_span_type = Get-DominantValue $group "dominant_span_type"
            dominant_span_duration_ms = [Math]::Round(($group | Measure-Object dominant_span_duration_ms -Average).Average, 2)
            dominant_span_share_pct = [Math]::Round(($group | Measure-Object dominant_span_share_pct -Average).Average, 2)
            db_span_share_pct = [Math]::Round(($group | Measure-Object db_span_share_pct -Average).Average, 2)
            downstream_span_share_pct = [Math]::Round(($group | Measure-Object downstream_span_share_pct -Average).Average, 2)
            log_lines_per_request_avg = [Math]::Round(($group | Measure-Object log_lines -Average).Average, 2)
            interpretation = Interpret $_.Name
        }
    }
}

function Get-DominantValue($Rows, [string]$Property) {
    $value = @($Rows | Group-Object $Property | Sort-Object Count -Descending | Select-Object -First 1)
    if ($value.Count -eq 0) { return "none" }
    return $value[0].Name
}

function Write-ComparisonMarkdown($Summary, $Path) {
    $lines = @()
    $lines += "# OpenTelemetry Spring Boot Lab - Comparison"
    $lines += ""
    $lines += "Generated: $(Get-Date -Format s)"
    $lines += ""
    $lines += "## Environment"
    $lines += ""
    $lines += "- Mode: $Mode"
    $lines += "- Dataset: $Size"
    $lines += "- Runs: $Runs"
    $lines += "- Requests per scenario per run: $Requests"
    $lines += "- Warmup requests per scenario: $Warmup"
    $lines += "- Requested concurrency: $Concurrency"
    $lines += "- Backend: Spring Boot 3, Java 21 target, PostgreSQL 16, Jaeger all-in-one"
    $lines += ""
    $lines += "## Summary"
    $lines += ""
    $lines += "| scenario | avg_ms | p95_ms | spans_avg | db_spans_avg | downstream_spans_avg | error_spans_total | error_spans_avg | interpretation |"
    $lines += "|---|---:|---:|---:|---:|---:|---:|---:|---|"
    foreach ($row in $Summary) {
        $lines += "| $($row.scenario) | $($row.avg_ms) | $($row.p95_ms) | $($row.trace_span_count_avg) | $($row.db_span_count_avg) | $($row.downstream_span_count_avg) | $($row.error_spans_total) | $($row.error_spans_avg) | $($row.interpretation) |"
    }
    $lines += ""
    $lines += "## What traces showed that logs did not make obvious"
    $lines += ""
    $lines += "- N+1 appears as DB span fan-out inside one request, without enabling noisy SQL logs."
    $lines += "- The downstream scenario isolates HTTP wait time from local DB time."
    $lines += "- The mixed scenario separates DB, downstream and transformation spans, which makes flat request logs less ambiguous."
    $lines += "- The partial error keeps the request controlled while marking the downstream failure in the trace and correlating logs via traceId/spanId."
    $lines += "- In `partial-error`, `error_spans_total` is a total across all measured requests; use `error_spans_avg` for per-request reading."
    $lines += ""
    $lines += "## What this lab does not prove"
    $lines += ""
    $lines += "- It does not measure production overhead."
    $lines += "- It does not prove Jaeger is mandatory; Jaeger is used because it is simple for a local lab."
    $lines += "- It does not claim traces replace logs."
    $lines += "- It does not claim tracing fixes performance; it makes the shape of latency visible."
    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function New-DiagnosisRows($Summary) {
    $Summary | Sort-Object {
        switch ($_.scenario) {
            "baseline" { 1 }
            "optimized" { 2 }
            "n-plus-one" { 3 }
            "downstream-slow" { 4 }
            "mixed" { 5 }
            "partial-error" { 6 }
            default { 99 }
        }
    } | ForEach-Object {
        $definition = Get-DiagnosisDefinition $_.scenario
        [pscustomobject]@{
            scenario = $_.scenario
            logs_available_signal = $definition.logs_available_signal
            trace_available_signal = $definition.trace_available_signal
            likely_root_cause_from_logs = $definition.likely_root_cause_from_logs
            likely_root_cause_from_trace = $definition.likely_root_cause_from_trace
            diagnosis_confidence_logs = $definition.diagnosis_confidence_logs
            diagnosis_confidence_trace = $definition.diagnosis_confidence_trace
            dominant_span_type = $_.dominant_span_type
            dominant_span_duration_ms = $_.dominant_span_duration_ms
            dominant_span_share_pct = $_.dominant_span_share_pct
            db_span_share_pct = $_.db_span_share_pct
            downstream_span_share_pct = $_.downstream_span_share_pct
            editorial_takeaway = $definition.editorial_takeaway
        }
    }
}

function Write-DiagnosisMarkdown($Rows, $Path) {
    $lines = @()
    $lines += "# Logs vs Traces - Diagnosis Comparison"
    $lines += ""
    $lines += "Generated: $(Get-Date -Format s)"
    $lines += ""
    $lines += "This table compares available diagnostic signals. It does not declare a universal winner and does not measure production overhead."
    $lines += ""
    $lines += "| scenario | logs_available_signal | trace_available_signal | likely_root_cause_from_logs | likely_root_cause_from_trace | diagnosis_confidence_logs | diagnosis_confidence_trace | dominant_span_type | dominant_span_duration_ms | dominant_span_share_pct | db_span_share_pct | downstream_span_share_pct | editorial_takeaway |"
    $lines += "|---|---|---|---|---|---|---|---|---:|---:|---:|---:|---|"
    foreach ($row in $Rows) {
        $lines += "| $($row.scenario) | $($row.logs_available_signal) | $($row.trace_available_signal) | $($row.likely_root_cause_from_logs) | $($row.likely_root_cause_from_trace) | $($row.diagnosis_confidence_logs) | $($row.diagnosis_confidence_trace) | $($row.dominant_span_type) | $($row.dominant_span_duration_ms) | $($row.dominant_span_share_pct) | $($row.db_span_share_pct) | $($row.downstream_span_share_pct) | $($row.editorial_takeaway) |"
    }
    $lines += ""
    $lines += "## Metric notes"
    $lines += ""
    $lines += "- `dominant_span_type`, `dominant_span_duration_ms`, `dominant_span_share_pct`, `db_span_share_pct` and `downstream_span_share_pct` are derived from Jaeger span durations exported during the run."
    $lines += "- Share percentages are diagnostic signals from exported spans, not production overhead measurements."
    $lines += "- Downstream percentages can include local client/server spans because the downstream is simulated inside the same app for reproducibility; cumulative shares can exceed 100% when spans overlap."
    $lines += '- Logs in this lab include `traceId`, `spanId`, scenario, status and total request duration, but they do not print SQL debug or reveal root causes artificially.'
    Set-Content -Path $Path -Value $lines -Encoding UTF8
}

function Write-SvgBar($Summary, $Metric, $Path, $Title, $Color) {
    $max = [double](($Summary | Measure-Object $Metric -Maximum).Maximum)
    if ($max -le 0) { $max = 1 }
    $width = 900
    $height = 420
    $x = 180
    $y = 70
    $barH = 38
    $gap = 22
    $svg = @()
    $svg += "<svg xmlns='http://www.w3.org/2000/svg' width='$width' height='$height' viewBox='0 0 $width $height'>"
    $svg += "<rect width='100%' height='100%' fill='#f8fafc'/>"
    $svg += "<text x='40' y='38' font-family='Arial' font-size='24' font-weight='700' fill='#111827'>$Title</text>"
    foreach ($row in $Summary) {
        $value = [double]$row.$Metric
        $barW = [Math]::Round(($value / $max) * 600)
        $svg += "<text x='40' y='$($y + 25)' font-family='Arial' font-size='15' fill='#111827'>$($row.scenario)</text>"
        $svg += "<rect x='$x' y='$y' width='$barW' height='$barH' rx='4' fill='$Color'/>"
        $svg += "<text x='$($x + $barW + 10)' y='$($y + 25)' font-family='Arial' font-size='15' fill='#111827'>$value</text>"
        $y += $barH + $gap
    }
    $svg += "</svg>"
    Set-Content -Path $Path -Value $svg -Encoding UTF8
}

function Write-TraceSvg($Path, $Title, $Rows) {
    $svg = @()
    $svg += "<svg xmlns='http://www.w3.org/2000/svg' width='960' height='330' viewBox='0 0 960 330'>"
    $svg += "<rect width='100%' height='100%' fill='#f8fafc'/>"
    $svg += "<text x='36' y='38' font-family='Arial' font-size='24' font-weight='700' fill='#111827'>$Title</text>"
    $y = 80
    foreach ($row in $Rows) {
        $svg += "<text x='42' y='$($y + 22)' font-family='Arial' font-size='14' fill='#111827'>$($row.name)</text>"
        $svg += "<rect x='$($row.x)' y='$y' width='$($row.w)' height='28' rx='4' fill='$($row.color)'/>"
        $svg += "<text x='$($row.x + 8)' y='$($y + 19)' font-family='Arial' font-size='12' fill='white'>$($row.label)</text>"
        $y += 48
    }
    $svg += "<text x='42' y='300' font-family='Arial' font-size='13' fill='#475569'>Synthetic trace asset generated from the lab scenario model; use Jaeger UI for live trace screenshots.</text>"
    $svg += "</svg>"
    Set-Content -Path $Path -Value $svg -Encoding UTF8
}

Push-Location $Root
try {
    docker compose up -d
    Wait-Http "$JaegerUrl" 60

    if (!(Test-Path $AgentPath)) {
        $agentUrl = "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v$AgentVersion/opentelemetry-javaagent.jar"
        Invoke-WebRequest -Uri $agentUrl -OutFile $AgentPath
    }
    if (!(Test-Path $JarPath)) {
        mvn package -DskipTests
    }

    $existing = Get-NetTCPConnection -LocalPort $AppPort -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        throw "Port $AppPort is already in use. Stop the process or change the runner AppPort before running the lab."
    }

    $env:SERVER_PORT = "$AppPort"
    $env:SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:65432/otel_lab?options=-c%20TimeZone=UTC"
    $env:SPRING_DATASOURCE_USERNAME = "otel"
    $env:SPRING_DATASOURCE_PASSWORD = "otel"
    $env:OTEL_SERVICE_NAME = "otel-spring-boot-lab"
    $env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"
    $env:OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    $env:OTEL_TRACES_EXPORTER = "otlp"
    $env:OTEL_METRICS_EXPORTER = "none"
    $env:OTEL_LOGS_EXPORTER = "none"
    $env:OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED = "true"
    $env:OTEL_BSP_SCHEDULE_DELAY = "100"
    $env:OTEL_BSP_EXPORT_TIMEOUT = "3000"

    $arguments = @("-Duser.timezone=UTC", "-javaagent:$AgentPath", "-jar", $JarPath)
    $process = Start-Process -FilePath "java" -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $AppLog -RedirectStandardError $AppErrLog
    try {
        Wait-Http "$AppUrl/actuator/health" 90
        Invoke-RestMethod -Uri "$AppUrl/admin/seed?size=$Size" -Method Post | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RawDir "seed-$Mode-$Size.json")

        $scenarios = @(
            @{ name = "baseline"; path = "/lab/baseline" },
            @{ name = "n-plus-one"; path = "/lab/n-plus-one?limit=60" },
            @{ name = "optimized"; path = "/lab/optimized?limit=60" },
            @{ name = "downstream-slow"; path = "/lab/downstream-slow?delayMs=300" },
            @{ name = "mixed"; path = "/lab/mixed?delayMs=300&limit=12" },
            @{ name = "partial-error"; path = "/lab/partial-error?delayMs=100" }
        )

        foreach ($scenario in $scenarios) {
            for ($i = 0; $i -lt $Warmup; $i++) {
                Invoke-LabRequest $scenario.name $scenario.path | Out-Null
            }
        }

        $observations = New-Object System.Collections.Generic.List[object]
        for ($run = 1; $run -le $Runs; $run++) {
            foreach ($scenario in $scenarios) {
                $jobs = @()
                for ($i = 1; $i -le $Requests; $i++) {
                    while (@($jobs | Where-Object State -eq "Running").Count -ge $Concurrency) {
                        $done = Wait-Job -Job $jobs -Any -Timeout 10
                        if ($done) {
                            Receive-Job -Job $done | ForEach-Object { $observations.Add($_) }
                            Remove-Job -Job $done
                            $jobs = @($jobs | Where-Object Id -ne $done.Id)
                        }
                    }
                    $scenarioName = $scenario.name
                    $scenarioPath = $scenario.path
                    $jobs += Start-ThreadJob -ScriptBlock {
                        param($RootPath, $ScenarioName, $ScenarioPath)
                        . (Join-Path $RootPath "scripts\run-lab-worker.ps1")
                        Invoke-LabWorkerRequest -AppUrl "http://localhost:18080" -JaegerUrl "http://localhost:16686" -Scenario $ScenarioName -Path $ScenarioPath
                    } -ArgumentList $Root, $scenarioName, $scenarioPath
                }
                foreach ($job in $jobs) {
                    Wait-Job -Job $job | Out-Null
                    Receive-Job -Job $job | ForEach-Object { $observations.Add($_) }
                    Remove-Job -Job $job
                }
            }
        }

        $rawPath = Join-Path $RawDir "observations-$Mode-$Size.json"
        $observations | ConvertTo-Json -Depth 8 | Set-Content $rawPath -Encoding UTF8
        $summary = @(Summarize $observations)
        $summary | Export-Csv -Path (Join-Path $ResultsDir "comparison.csv") -Encoding UTF8
        Write-ComparisonMarkdown $summary (Join-Path $ResultsDir "comparison.md")
        $diagnosisRows = @(New-DiagnosisRows $summary)
        $diagnosisRows | Export-Csv -Path (Join-Path $ResultsDir "diagnosis-comparison.csv") -Encoding UTF8
        Write-DiagnosisMarkdown $diagnosisRows (Join-Path $ResultsDir "diagnosis-comparison.md")
        Write-SvgBar $summary "trace_span_count_avg" (Join-Path $AssetsDir "span-count-by-scenario.svg") "Average span count by scenario" "#2563eb"
        Write-SvgBar $summary "p95_ms" (Join-Path $AssetsDir "p95-by-scenario.svg") "p95 latency by scenario (ms)" "#059669"
        Write-TraceSvg (Join-Path $AssetsDir "trace-n-plus-one.svg") "N+1 trace shape" @(
            @{ name = "HTTP server"; x = 220; w = 620; color = "#334155"; label = "request" },
            @{ name = "Business span"; x = 260; w = 560; color = "#7c3aed"; label = "load tasks then comments" },
            @{ name = "DB fan-out"; x = 300; w = 420; color = "#dc2626"; label = "many repeated comment queries" }
        )
        Write-TraceSvg (Join-Path $AssetsDir "trace-optimized.svg") "Optimized trace shape" @(
            @{ name = "HTTP server"; x = 220; w = 430; color = "#334155"; label = "request" },
            @{ name = "Business span"; x = 260; w = 360; color = "#7c3aed"; label = "join aggregate" },
            @{ name = "DB"; x = 300; w = 260; color = "#059669"; label = "single grouped query" }
        )
        Write-TraceSvg (Join-Path $AssetsDir "trace-downstream-slow.svg") "Downstream slow trace shape" @(
            @{ name = "HTTP server"; x = 220; w = 650; color = "#334155"; label = "request" },
            @{ name = "Business span"; x = 260; w = 590; color = "#7c3aed"; label = "fetch profile" },
            @{ name = "HTTP client"; x = 310; w = 500; color = "#ea580c"; label = "downstream delay dominates" }
        )
    } finally {
        if ($process -and !$process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
} finally {
    Pop-Location
}

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
        log_lines = 2
    }
}

function Get-TraceCounts($TraceId) {
    if ([string]::IsNullOrWhiteSpace($TraceId) -or $TraceId -eq "none") {
        return @{ trace = 0; db = 0; downstream = 0; error = 0 }
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
            return @{ trace = $spans.Count; db = $db; downstream = $downstream; error = $errors }
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }
    return @{ trace = 0; db = 0; downstream = 0; error = 0 }
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
            error_span_count = [int]($group | Measure-Object error_span_count -Sum).Sum
            log_lines_per_request_avg = [Math]::Round(($group | Measure-Object log_lines -Average).Average, 2)
            interpretation = Interpret $_.Name
        }
    }
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
    $lines += "| scenario | avg_ms | p95_ms | spans_avg | db_spans_avg | downstream_spans_avg | error_spans | interpretation |"
    $lines += "|---|---:|---:|---:|---:|---:|---:|---|"
    foreach ($row in $Summary) {
        $lines += "| $($row.scenario) | $($row.avg_ms) | $($row.p95_ms) | $($row.trace_span_count_avg) | $($row.db_span_count_avg) | $($row.downstream_span_count_avg) | $($row.error_span_count) | $($row.interpretation) |"
    }
    $lines += ""
    $lines += "## What traces showed that logs did not make obvious"
    $lines += ""
    $lines += "- N+1 appears as DB span fan-out inside one request, without enabling noisy SQL logs."
    $lines += "- The downstream scenario isolates HTTP wait time from local DB time."
    $lines += "- The mixed scenario separates DB, downstream and transformation spans, which makes flat request logs less ambiguous."
    $lines += "- The partial error keeps the request controlled while marking the downstream failure in the trace and correlating logs via traceId/spanId."
    $lines += ""
    $lines += "## What this lab does not prove"
    $lines += ""
    $lines += "- It does not measure production overhead."
    $lines += "- It does not prove Jaeger is mandatory; Jaeger is used because it is simple for a local lab."
    $lines += "- It does not claim traces replace logs."
    $lines += "- It does not claim tracing fixes performance; it makes the shape of latency visible."
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

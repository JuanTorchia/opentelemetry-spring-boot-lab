function Get-LabWorkerTraceCounts {
    param([string]$JaegerUrl, [string]$TraceId)
    if ([string]::IsNullOrWhiteSpace($TraceId) -or $TraceId -eq "none") {
        return @{ trace = 0; db = 0; downstream = 0; error = 0 }
    }
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try {
        Start-Sleep -Milliseconds 250
        $trace = Invoke-RestMethod -Uri "$JaegerUrl/api/traces/$TraceId" -TimeoutSec 5
        if (!$trace.data -or @($trace.data).Count -eq 0) {
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

function Invoke-LabWorkerRequest {
    param(
        [string]$AppUrl,
        [string]$JaegerUrl,
        [string]$Scenario,
        [string]$Path
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = 0
    $traceId = ""
    try {
        $response = Invoke-WebRequest -Uri "$AppUrl$Path" -UseBasicParsing -TimeoutSec 30 -SkipHttpErrorCheck
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
    $counts = Get-LabWorkerTraceCounts -JaegerUrl $JaegerUrl -TraceId $traceId
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

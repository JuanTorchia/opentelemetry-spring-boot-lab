function Get-LabWorkerSpanTagValue {
    param($Span, [string]$Key)
    $tag = @($Span.tags | Where-Object { $_.key -eq $Key } | Select-Object -First 1)
    if ($tag.Count -eq 0) { return $null }
    return $tag[0].value
}

function Test-LabWorkerDbSpan {
    param($Span)
    return [bool](@($Span.tags | Where-Object { $_.key -eq "db.system" -or $_.key -eq "db.system.name" }).Count)
}

function Test-LabWorkerDownstreamSpan {
    param($Span)
    $path = Get-LabWorkerSpanTagValue -Span $Span -Key "url.path"
    return ($Span.operationName -like "*downstream*") -or ($path -like "*downstream*")
}

function Get-LabWorkerEmptyTraceCounts {
    return @{
        trace = 0; db = 0; downstream = 0; error = 0
        dominant_type = "none"; dominant_duration_ms = 0; dominant_share_pct = 0
        db_share_pct = 0; downstream_share_pct = 0
    }
}

function Get-LabWorkerSpanDiagnostics {
    param($Spans)
    $all = @($Spans)
    if ($all.Count -eq 0) {
        return Get-LabWorkerEmptyTraceCounts
    }
    $rootDurationUs = [double](($all | Measure-Object duration -Maximum).Maximum)
    if ($rootDurationUs -le 0) { $rootDurationUs = 1 }
    $classified = $all | ForEach-Object {
        $type = if (Test-LabWorkerDbSpan $_) {
            "db"
        } elseif (Test-LabWorkerDownstreamSpan $_) {
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

function Get-LabWorkerTraceCounts {
    param([string]$JaegerUrl, [string]$TraceId)
    if ([string]::IsNullOrWhiteSpace($TraceId) -or $TraceId -eq "none") {
        return Get-LabWorkerEmptyTraceCounts
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
            $diagnostics = Get-LabWorkerSpanDiagnostics -Spans $spans
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
    return Get-LabWorkerEmptyTraceCounts
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
        dominant_span_type = $counts.dominant_type
        dominant_span_duration_ms = $counts.dominant_duration_ms
        dominant_span_share_pct = $counts.dominant_share_pct
        db_span_share_pct = $counts.db_share_pct
        downstream_span_share_pct = $counts.downstream_share_pct
        log_lines = 3
    }
}

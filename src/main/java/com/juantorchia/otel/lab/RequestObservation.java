package com.juantorchia.otel.lab;

public record RequestObservation(
        boolean successful,
        long durationMs,
        int traceSpanCount,
        int dbSpanCount,
        int downstreamSpanCount,
        int errorSpanCount,
        int logLines) {

    public static RequestObservation success(
            long durationMs, int traceSpanCount, int dbSpanCount, int downstreamSpanCount, int logLines) {
        return new RequestObservation(true, durationMs, traceSpanCount, dbSpanCount, downstreamSpanCount, 0, logLines);
    }

    public static RequestObservation error(
            long durationMs, int traceSpanCount, int dbSpanCount, int errorSpanCount, int logLines) {
        return new RequestObservation(false, durationMs, traceSpanCount, dbSpanCount, 0, errorSpanCount, logLines);
    }
}

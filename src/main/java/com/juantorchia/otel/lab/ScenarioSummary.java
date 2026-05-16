package com.juantorchia.otel.lab;

import java.util.Comparator;
import java.util.List;

public record ScenarioSummary(
        String scenario,
        String mode,
        int totalRequests,
        int successfulRequests,
        double errorRate,
        long avgMs,
        long p50Ms,
        long p95Ms,
        long p99Ms,
        double traceSpanCountAvg,
        double dbSpanCountAvg,
        double downstreamSpanCountAvg,
        int errorSpanCount,
        double logLinesPerRequestAvg,
        String interpretation) {

    public static ScenarioSummary from(String scenario, String mode, List<RequestObservation> observations) {
        if (observations.isEmpty()) {
            throw new IllegalArgumentException("observations must not be empty");
        }
        List<Long> durations = observations.stream()
                .map(RequestObservation::durationMs)
                .sorted(Comparator.naturalOrder())
                .toList();
        int total = observations.size();
        int success = (int) observations.stream().filter(RequestObservation::successful).count();
        return new ScenarioSummary(
                scenario,
                mode,
                total,
                success,
                round((double) (total - success) / total),
                Math.round(observations.stream().mapToLong(RequestObservation::durationMs).average().orElse(0)),
                percentile(durations, 0.50),
                percentile(durations, 0.95),
                percentile(durations, 0.99),
                round(observations.stream().mapToInt(RequestObservation::traceSpanCount).average().orElse(0)),
                round(observations.stream().mapToInt(RequestObservation::dbSpanCount).average().orElse(0)),
                round(observations.stream().mapToInt(RequestObservation::downstreamSpanCount).average().orElse(0)),
                observations.stream().mapToInt(RequestObservation::errorSpanCount).sum(),
                round(observations.stream().mapToInt(RequestObservation::logLines).average().orElse(0)),
                ScenarioInterpretation.forScenario(scenario));
    }

    private static long percentile(List<Long> sorted, double percentile) {
        int index = (int) Math.ceil(percentile * sorted.size()) - 1;
        return sorted.get(Math.max(0, Math.min(index, sorted.size() - 1)));
    }

    private static double round(double value) {
        return Math.round(value * 100.0) / 100.0;
    }
}

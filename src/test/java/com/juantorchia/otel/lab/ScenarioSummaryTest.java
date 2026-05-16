package com.juantorchia.otel.lab;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;

class ScenarioSummaryTest {

    @Test
    void calculatesPercentilesAndErrorRate() {
        ScenarioSummary summary = ScenarioSummary.from(
                "n-plus-one",
                "smoke",
                List.of(
                        RequestObservation.success(100, 8, 6, 0, 12),
                        RequestObservation.success(200, 9, 7, 0, 14),
                        RequestObservation.error(300, 10, 7, 1, 18),
                        RequestObservation.success(400, 11, 8, 0, 16)));

        assertThat(summary.totalRequests()).isEqualTo(4);
        assertThat(summary.successfulRequests()).isEqualTo(3);
        assertThat(summary.errorRate()).isEqualTo(0.25);
        assertThat(summary.avgMs()).isEqualTo(250);
        assertThat(summary.p50Ms()).isEqualTo(200);
        assertThat(summary.p95Ms()).isEqualTo(400);
        assertThat(summary.p99Ms()).isEqualTo(400);
        assertThat(summary.traceSpanCountAvg()).isEqualTo(9.5);
        assertThat(summary.dbSpanCountAvg()).isEqualTo(7.0);
        assertThat(summary.errorSpanCount()).isEqualTo(1);
        assertThat(summary.logLinesPerRequestAvg()).isEqualTo(15.0);
    }
}

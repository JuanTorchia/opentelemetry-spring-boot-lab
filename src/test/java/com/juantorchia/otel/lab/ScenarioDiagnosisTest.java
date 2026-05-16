package com.juantorchia.otel.lab;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ScenarioDiagnosisTest {

    @Test
    void nPlusOneContrastsAmbiguousLogsWithDbFanOutTrace() {
        ScenarioDiagnosis diagnosis = ScenarioDiagnosis.forScenario("n-plus-one");

        assertThat(diagnosis.logsAvailableSignal()).contains("status OK").contains("duracion total");
        assertThat(diagnosis.traceAvailableSignal()).contains("DB spans").contains("fan-out");
        assertThat(diagnosis.likelyRootCauseFromLogs()).contains("ambiguo");
        assertThat(diagnosis.likelyRootCauseFromTrace()).contains("N+1");
        assertThat(diagnosis.diagnosisConfidenceLogs()).isEqualTo("low");
        assertThat(diagnosis.diagnosisConfidenceTrace()).isEqualTo("high");
    }

    @Test
    void partialErrorKeepsLogsUsefulButTraceMoreSpecific() {
        ScenarioDiagnosis diagnosis = ScenarioDiagnosis.forScenario("partial-error");

        assertThat(diagnosis.logsAvailableSignal()).contains("traceId").contains("spanId");
        assertThat(diagnosis.traceAvailableSignal()).contains("spans marcados con error");
        assertThat(diagnosis.diagnosisConfidenceLogs()).isEqualTo("medium");
        assertThat(diagnosis.diagnosisConfidenceTrace()).isEqualTo("high");
    }
}

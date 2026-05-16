package com.juantorchia.otel.lab;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ScenarioInterpretationTest {

    @Test
    void explainsNPlusOneAsDbFanOutRatherThanGenericSlowness() {
        String interpretation = ScenarioInterpretation.forScenario("n-plus-one");

        assertThat(interpretation)
                .contains("DB")
                .contains("spans")
                .contains("N+1");
    }

    @Test
    void explainsDownstreamAsHttpLatencyOutsideDb() {
        String interpretation = ScenarioInterpretation.forScenario("downstream-slow");

        assertThat(interpretation)
                .contains("downstream")
                .contains("HTTP")
                .contains("DB");
    }
}

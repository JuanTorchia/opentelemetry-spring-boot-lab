package com.juantorchia.otel.lab;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class SeedPlanTest {

    @Test
    void smallSizeUsesOneThousandTasks() {
        SeedPlan plan = SeedPlan.from("small");

        assertThat(plan.taskCount()).isEqualTo(1_000);
        assertThat(plan.userCount()).isEqualTo(40);
        assertThat(plan.projectCount()).isEqualTo(10);
    }

    @Test
    void editorialSizeUsesFiftyThousandTasks() {
        SeedPlan plan = SeedPlan.from("editorial");

        assertThat(plan.taskCount()).isEqualTo(50_000);
        assertThat(plan.userCount()).isEqualTo(400);
        assertThat(plan.projectCount()).isEqualTo(80);
    }
}

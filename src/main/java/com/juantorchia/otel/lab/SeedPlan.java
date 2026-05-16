package com.juantorchia.otel.lab;

public record SeedPlan(String size, int organizationCount, int userCount, int projectCount, int taskCount) {

    public static SeedPlan from(String size) {
        return switch (size == null ? "small" : size.toLowerCase()) {
            case "small" -> new SeedPlan("small", 5, 40, 10, 1_000);
            case "editorial" -> new SeedPlan("editorial", 10, 400, 80, 50_000);
            default -> throw new IllegalArgumentException("Unknown dataset size: " + size);
        };
    }
}

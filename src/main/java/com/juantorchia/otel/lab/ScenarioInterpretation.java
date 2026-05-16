package com.juantorchia.otel.lab;

public final class ScenarioInterpretation {

    private ScenarioInterpretation() {
    }

    public static String forScenario(String scenario) {
        return switch (scenario) {
            case "baseline" -> "Request simple: pocos spans, DB acotada y logs suficientes para confirmar OK.";
            case "n-plus-one" -> "N+1 visible como fan-out de spans DB; los logs sólo dicen OK si no se activa logging SQL invasivo.";
            case "optimized" -> "Mismo resultado de negocio que N+1 con menos spans DB y menor duración acumulada.";
            case "downstream-slow" -> "La latencia está en HTTP/downstream, no en DB; el trace separa espera externa de consulta local.";
            case "mixed" -> "DB, downstream y transformación compiten; el trace muestra distribución por etapa mejor que logs planos.";
            case "partial-error" -> "El error parcial aparece con status/error span y se puede correlacionar con traceId/spanId en logs.";
            default -> "Escenario no documentado; revisar raw results antes de interpretar.";
        };
    }
}

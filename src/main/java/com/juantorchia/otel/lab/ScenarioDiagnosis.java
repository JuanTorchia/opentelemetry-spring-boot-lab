package com.juantorchia.otel.lab;

public record ScenarioDiagnosis(
        String scenario,
        String logsAvailableSignal,
        String traceAvailableSignal,
        String likelyRootCauseFromLogs,
        String likelyRootCauseFromTrace,
        String diagnosisConfidenceLogs,
        String diagnosisConfidenceTrace,
        String editorialTakeaway) {

    public static ScenarioDiagnosis forScenario(String scenario) {
        return switch (scenario) {
            case "baseline" -> new ScenarioDiagnosis(
                    scenario,
                    "status OK, duracion total baja, traceId/spanId para correlacion",
                    "pocos spans, una consulta DB compacta, sin error",
                    "request saludable, sin causa raiz que investigar",
                    "request saludable, DB acotada",
                    "high",
                    "high",
                    "El trace no agrega dramatismo cuando la request es simple; confirma la forma esperada.");
            case "optimized" -> new ScenarioDiagnosis(
                    scenario,
                    "status OK, duracion total baja, resultado de negocio correcto",
                    "pocos DB spans y una agregacion visible",
                    "probablemente saludable, pero no prueba por si solo que no haya fan-out interno",
                    "consulta agregada sin fan-out DB relevante",
                    "medium",
                    "high",
                    "La comparacion con N+1 funciona porque el trace muestra menos spans para el mismo shape funcional.");
            case "n-plus-one" -> new ScenarioDiagnosis(
                    scenario,
                    "status OK, duracion total elevada o ruidosa, traceId/spanId para buscar el caso",
                    "muchos DB spans dentro de una sola request, fan-out visible",
                    "ambiguo; requiere SQL logs, inspeccion extra o conocimiento previo del codigo",
                    "DB fan-out / N+1",
                    "low",
                    "high",
                    "Sin SQL debug, los logs sugieren lentitud; el trace muestra la forma repetitiva de la causa.");
            case "downstream-slow" -> new ScenarioDiagnosis(
                    scenario,
                    "status OK, duracion total cercana al delay configurado",
                    "tiempo concentrado en spans HTTP/downstream",
                    "posible espera externa, pero DB y transformacion quedan poco separadas",
                    "downstream lento domina la request",
                    "medium",
                    "high",
                    "El trace separa espera externa de trabajo local sin convertir los logs en SQL/HTTP debug.");
            case "mixed" -> new ScenarioDiagnosis(
                    scenario,
                    "status OK, duracion total alta, eventos de negocio por escenario",
                    "spans DB, downstream y transformacion ordenados temporalmente",
                    "ambiguo; varias etapas plausibles compiten como causa dominante",
                    "distribucion causal entre DB, downstream y transformacion",
                    "low",
                    "high",
                    "El caso mixto es donde el trace aporta mas contexto causal frente a logs planos.");
            case "partial-error" -> new ScenarioDiagnosis(
                    scenario,
                    "error controlado con status parcial, traceId/spanId y tipo de excepcion",
                    "spans marcados con error dentro de una request parcialmente exitosa",
                    "fallo downstream controlado, aunque cuesta ver su posicion causal exacta",
                    "downstream fallo dentro de una request que responde parcialmente",
                    "medium",
                    "high",
                    "Logs y traces se complementan: el log avisa, el trace ubica el error en la jerarquia.");
            default -> throw new IllegalArgumentException("Unknown scenario: " + scenario);
        };
    }
}

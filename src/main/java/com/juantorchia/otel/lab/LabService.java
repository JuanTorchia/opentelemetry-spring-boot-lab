package com.juantorchia.otel.lab;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

@Service
public class LabService {

    private static final Logger log = LoggerFactory.getLogger(LabService.class);
    private final JdbcTemplate jdbcTemplate;
    private final WebClient downstreamClient;
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("otel-spring-boot-lab");

    public LabService(JdbcTemplate jdbcTemplate, WebClient downstreamClient) {
        this.jdbcTemplate = jdbcTemplate;
        this.downstreamClient = downstreamClient;
    }

    public Map<String, Object> baseline() {
        log.info("scenario=baseline start");
        Span span = tracer.spanBuilder("business.baseline.query").startSpan();
        try (var ignored = span.makeCurrent()) {
            Map<String, Object> row = jdbcTemplate.queryForMap("""
                    select count(*) as tasks,
                           count(*) filter (where status = 'blocked') as blocked,
                           avg(estimate_minutes)::int as avg_estimate
                    from tasks
                    """);
            span.setAttribute("lab.tasks", ((Number) row.get("tasks")).longValue());
            log.info("scenario=baseline ok tasks={}", row.get("tasks"));
            return Map.of("scenario", "baseline", "summary", row);
        } finally {
            span.end();
        }
    }

    public Map<String, Object> nPlusOne(int limit) {
        log.info("scenario=n-plus-one start limit={}", limit);
        Span span = tracer.spanBuilder("business.n_plus_one.load_tasks_then_comments").startSpan();
        try (var ignored = span.makeCurrent()) {
            List<Map<String, Object>> tasks = jdbcTemplate.queryForList("""
                    select t.id, t.title, u.display_name as assignee
                    from tasks t
                    join users u on u.id = t.assignee_id
                    order by t.id
                    limit ?
                    """, limit);
            List<Map<String, Object>> enriched = new ArrayList<>();
            for (Map<String, Object> task : tasks) {
                Long taskId = ((Number) task.get("id")).longValue();
                Integer comments = jdbcTemplate.queryForObject(
                        "select count(*) from comments where task_id = ?",
                        Integer.class,
                        taskId);
                enriched.add(Map.of(
                        "id", taskId,
                        "title", task.get("title"),
                        "assignee", task.get("assignee"),
                        "comments", comments == null ? 0 : comments));
            }
            span.setAttribute("lab.n_plus_one.items", enriched.size());
            span.setAttribute("lab.n_plus_one.expected_extra_queries", enriched.size());
            log.info("scenario=n-plus-one ok tasks={}", enriched.size());
            return Map.of("scenario", "n-plus-one", "tasks", enriched);
        } finally {
            span.end();
        }
    }

    public Map<String, Object> optimized(int limit) {
        log.info("scenario=optimized start limit={}", limit);
        Span span = tracer.spanBuilder("business.optimized.join_aggregate").startSpan();
        try (var ignored = span.makeCurrent()) {
            List<Map<String, Object>> tasks = jdbcTemplate.queryForList("""
                    select t.id, t.title, u.display_name as assignee, count(c.id)::int as comments
                    from tasks t
                    join users u on u.id = t.assignee_id
                    left join comments c on c.task_id = t.id
                    group by t.id, t.title, u.display_name
                    order by t.id
                    limit ?
                    """, limit);
            span.setAttribute("lab.optimized.items", tasks.size());
            log.info("scenario=optimized ok tasks={}", tasks.size());
            return Map.of("scenario", "optimized", "tasks", tasks);
        } finally {
            span.end();
        }
    }

    public Map<String, Object> downstreamSlow(int delayMs) {
        log.info("scenario=downstream-slow start delayMs={}", delayMs);
        Span span = tracer.spanBuilder("business.downstream.fetch_profile").startSpan();
        try (var ignored = span.makeCurrent()) {
            Map<?, ?> response = downstreamClient.get()
                    .uri(uriBuilder -> uriBuilder
                            .path("/downstream/profile")
                            .queryParam("delayMs", delayMs)
                            .build())
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofSeconds(3))
                    .block();
            span.setAttribute("lab.downstream.delay_ms", delayMs);
            log.info("scenario=downstream-slow ok delayMs={}", delayMs);
            return Map.of("scenario", "downstream-slow", "downstream", response == null ? Map.of() : response);
        } finally {
            span.end();
        }
    }

    public Map<String, Object> mixed(int delayMs, int limit) {
        log.info("scenario=mixed start delayMs={} limit={}", delayMs, limit);
        Span dbSpan = tracer.spanBuilder("business.mixed.db_summary").startSpan();
        List<Map<String, Object>> rows;
        try (var ignored = dbSpan.makeCurrent()) {
            rows = jdbcTemplate.queryForList("""
                    select p.id as project_id, p.name, count(t.id)::int as tasks, sum(t.estimate_minutes)::int as minutes
                    from projects p
                    join tasks t on t.project_id = p.id
                    group by p.id, p.name
                    order by tasks desc
                    limit ?
                    """, limit);
            dbSpan.setAttribute("lab.mixed.projects", rows.size());
        } finally {
            dbSpan.end();
        }
        Map<String, Object> downstream = downstreamSlow(delayMs);
        Span transformSpan = tracer.spanBuilder("business.mixed.transform").startSpan();
        try (var ignored = transformSpan.makeCurrent()) {
            List<Map<String, Object>> transformed = rows.stream()
                    .map(row -> {
                        long minutes = ((Number) row.get("minutes")).longValue();
                        return Map.of(
                                "projectId", row.get("project_id"),
                                "name", row.get("name"),
                                "tasks", row.get("tasks"),
                                "hours", Math.round(minutes / 60.0),
                                "risk", minutes > 60_000 ? "high" : "normal");
                    })
                    .sorted(Comparator.comparing(row -> row.get("name").toString()))
                    .toList();
            transformSpan.setAttribute("lab.mixed.transformed", transformed.size());
            log.info("scenario=mixed ok projects={}", transformed.size());
            return Map.of("scenario", "mixed", "projects", transformed, "downstream", downstream.get("downstream"));
        } finally {
            transformSpan.end();
        }
    }

    public Map<String, Object> partialError(int delayMs) {
        log.info("scenario=partial-error start delayMs={}", delayMs);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scenario", "partial-error");
        result.put("db", baseline().get("summary"));
        Span span = tracer.spanBuilder("business.partial_error.downstream").startSpan();
        try (var ignored = span.makeCurrent()) {
            downstreamClient.get()
                    .uri(uriBuilder -> uriBuilder
                            .path("/downstream/profile")
                            .queryParam("delayMs", delayMs)
                            .queryParam("fail", true)
                            .build())
                    .retrieve()
                    .bodyToMono(Map.class)
                    .timeout(Duration.ofMillis(Math.max(250, delayMs + 100L)))
                    .block();
            result.put("downstream", "unexpected-success");
        } catch (RuntimeException ex) {
            span.recordException(ex);
            span.setStatus(StatusCode.ERROR, "controlled downstream failure");
            result.put("downstream", "partial-failure");
            result.put("error", ex.getClass().getSimpleName());
            log.warn("scenario=partial-error downstream_failed type={}", ex.getClass().getSimpleName());
        } finally {
            span.end();
        }
        return result;
    }
}

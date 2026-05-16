package com.juantorchia.otel.lab;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DatabaseSeeder {

    private final JdbcTemplate jdbcTemplate;
    private final Tracer tracer = GlobalOpenTelemetry.getTracer("otel-spring-boot-lab");

    public DatabaseSeeder(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public Map<String, Object> seed(String size) {
        SeedPlan plan = SeedPlan.from(size);
        Span span = tracer.spanBuilder("seed.dataset").startSpan();
        try (var ignored = span.makeCurrent()) {
            span.setAttribute("lab.dataset.size", plan.size());
            span.setAttribute("lab.dataset.tasks", plan.taskCount());
            recreateSchema();
            insertData(plan);
            return Map.of(
                    "size", plan.size(),
                    "organizations", plan.organizationCount(),
                    "users", plan.userCount(),
                    "projects", plan.projectCount(),
                    "tasks", plan.taskCount(),
                    "comments", plan.taskCount() * 2);
        } finally {
            span.end();
        }
    }

    public Map<String, Object> status() {
        Integer tasks = jdbcTemplate.queryForObject("select count(*) from tasks", Integer.class);
        Integer comments = jdbcTemplate.queryForObject("select count(*) from comments", Integer.class);
        return Map.of("tasks", tasks == null ? 0 : tasks, "comments", comments == null ? 0 : comments);
    }

    private void recreateSchema() {
        jdbcTemplate.execute("drop table if exists comments");
        jdbcTemplate.execute("drop table if exists tasks");
        jdbcTemplate.execute("drop table if exists projects");
        jdbcTemplate.execute("drop table if exists users");
        jdbcTemplate.execute("drop table if exists organizations");
        jdbcTemplate.execute("""
                create table organizations (
                  id bigint primary key,
                  name text not null
                )
                """);
        jdbcTemplate.execute("""
                create table users (
                  id bigint primary key,
                  organization_id bigint not null references organizations(id),
                  display_name text not null
                )
                """);
        jdbcTemplate.execute("""
                create table projects (
                  id bigint primary key,
                  organization_id bigint not null references organizations(id),
                  name text not null
                )
                """);
        jdbcTemplate.execute("""
                create table tasks (
                  id bigint primary key,
                  project_id bigint not null references projects(id),
                  assignee_id bigint not null references users(id),
                  status text not null,
                  title text not null,
                  estimate_minutes int not null
                )
                """);
        jdbcTemplate.execute("""
                create table comments (
                  id bigint primary key,
                  task_id bigint not null references tasks(id),
                  body text not null
                )
                """);
        jdbcTemplate.execute("create index idx_tasks_project on tasks(project_id)");
        jdbcTemplate.execute("create index idx_tasks_assignee on tasks(assignee_id)");
        jdbcTemplate.execute("create index idx_comments_task on comments(task_id)");
    }

    private void insertData(SeedPlan plan) {
        jdbcTemplate.update("""
                insert into organizations(id, name)
                select gs, 'org-' || gs
                from generate_series(1, ?) gs
                """, plan.organizationCount());
        jdbcTemplate.update("""
                insert into users(id, organization_id, display_name)
                select gs, ((gs - 1) % ?) + 1, 'user-' || gs
                from generate_series(1, ?) gs
                """, plan.organizationCount(), plan.userCount());
        jdbcTemplate.update("""
                insert into projects(id, organization_id, name)
                select gs, ((gs - 1) % ?) + 1, 'project-' || gs
                from generate_series(1, ?) gs
                """, plan.organizationCount(), plan.projectCount());
        jdbcTemplate.update("""
                insert into tasks(id, project_id, assignee_id, status, title, estimate_minutes)
                select gs,
                       ((gs - 1) % ?) + 1,
                       ((gs - 1) % ?) + 1,
                       case when gs % 7 = 0 then 'blocked' when gs % 3 = 0 then 'review' else 'open' end,
                       'task-' || gs,
                       15 + (gs % 240)
                from generate_series(1, ?) gs
                """, plan.projectCount(), plan.userCount(), plan.taskCount());
        jdbcTemplate.update("""
                insert into comments(id, task_id, body)
                select gs, ((gs - 1) % ?) + 1, 'comment-' || gs
                from generate_series(1, ?) gs
                """, plan.taskCount(), plan.taskCount() * 2);
    }
}

# OpenTelemetry Spring Boot Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Spring Boot 3 laboratory that produces trace/log evidence for an editorial post about OpenTelemetry.

**Architecture:** A single Spring Boot app exposes lab scenarios and a synthetic downstream endpoint. Docker Compose provides PostgreSQL 16 and Jaeger. PowerShell orchestrates build, seed, instrumented app startup, requests, Jaeger trace collection, CSV/Markdown reporting and SVG assets.

**Tech Stack:** Spring Boot 3, Java 21 target, Maven, PostgreSQL 16, Docker Compose, OpenTelemetry Java Agent, Jaeger, PowerShell, Bash wrapper.

---

### Task 1: Project skeleton and tests

**Files:**
- Create: `pom.xml`
- Create: `src/test/java/com/juantorchia/otel/lab/SeedPlanTest.java`
- Create: `src/test/java/com/juantorchia/otel/lab/ScenarioSummaryTest.java`
- Create: `src/test/java/com/juantorchia/otel/lab/ScenarioInterpretationTest.java`

- [x] Write failing tests for dataset sizes, summary metrics and scenario interpretation.
- [x] Run `mvn test` and verify compilation fails because production classes do not exist.
- [x] Add minimal production classes to satisfy tests.
- [x] Run `mvn test -q`.

### Task 2: Spring Boot app and scenarios

**Files:**
- Create: `src/main/java/com/juantorchia/otel/lab/*.java`
- Create: `src/main/resources/application.yml`
- Create: `src/main/resources/logback-spring.xml`

- [x] Add Spring Boot entrypoint.
- [x] Add deterministic Postgres schema and seed service.
- [x] Add endpoints for baseline, N+1, optimized, downstream slow, mixed and partial error.
- [x] Add manual spans for business sections.
- [x] Add `traceId` and `spanId` log pattern.
- [x] Add response headers for trace correlation.

### Task 3: Runtime and runner

**Files:**
- Create: `docker-compose.yml`
- Create: `scripts/run-lab.ps1`
- Create: `scripts/run-lab-worker.ps1`
- Create: `scripts/run-lab.sh`

- [x] Compose PostgreSQL 16 and Jaeger all-in-one.
- [x] Runner starts Compose, downloads Java Agent, starts app, seeds data, executes scenarios, queries Jaeger and writes results.
- [x] Runner generates comparison CSV/Markdown and SVG assets.

### Task 4: Documentation

**Files:**
- Create: `README.md`
- Create: `docs/brief-post.md`
- Create: `.gitignore`

- [x] Document what is measured, smoke/editorial commands, Jaeger UI, interpretation, asset regeneration, limitations and cleanup.
- [x] Write editorial brief with thesis, defendable findings, prohibited claims and limitations.

### Task 5: Verification and release

**Commands:**
- `mvn test`
- `mvn package`
- `docker compose config --quiet`
- `.\scripts\run-lab.ps1 -Mode smoke -Size small`
- `.\scripts\run-lab.ps1 -Mode editorial -Size editorial -Runs 3 -Requests 200 -Warmup 20 -Concurrency 8`
- secret scan with `rg`
- git init, commit, remote push, tag `editorial-final`

- [ ] Run required verification commands.
- [ ] Fix failures.
- [ ] Commit and push final state.

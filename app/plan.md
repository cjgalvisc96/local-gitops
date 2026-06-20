# TODO App — Implementation Plan

> Companion to `todo-app-architecture-summary.md` and `project-structure.md`. This document sequences the work into phases an agent team (or a solo dev) can execute in order, with explicit dependencies between phases.

---

## 0. Guiding Constraints

These hold across every phase and should be checked before merging any work:

- **Dependency direction**: `domain → application → infrastructure`, never reversed. Only each context's `container.py` is allowed to import across all three layers.
- **Context isolation**: `users`, `tasks`, `shared` never import each other's internals directly. Cross-context access goes through a sub-container injected at the root (`ApplicationContainer`) or domain events.
- **Presentation purity**: `api/` and `cli/` contain no business logic — they call `application/` use cases (commands/queries) only.
- **Serializers depend on entities, not DB models.** A DB model change must never force an API contract change without an explicit mapper update.
- **Auth provider**: **AWS Cognito** is the single source of truth for authentication (JWT) and SSO across both the application (`users/infrastructure/auth/`) and infrastructure (`infra/terraform/modules/cognito/`). No Keycloak or other IdP.

---

## 1. Phase Overview

| Phase | Name | Goal |
|---|---|---|
| 1 | Foundations | Repo, tooling, env, Taskfile, Docker skeleton |
| 2 | Domain Core | `shared` kernel + base model, `users` and `tasks` domain layers |
| 3 | Application Layer | Use cases (commands/queries), DTOs, repository ports |
| 4 | Infrastructure | SQLAlchemy models, repos, Atlas migrations, Redis, Cognito client |
| 5 | DI Composition | Per-context containers + root `ApplicationContainer` |
| 6 | Presentation — API | FastAPI builder, routers, serializers, middleware, health |
| 7 | Presentation — CLI | Typer commands mirroring application use cases |
| 8 | Testing & Governance | pytest pyramid, coverage, import-linter, vulture, pyright |
| 9 | Local DevOps (floci) | Helm chart, K8s manifests, local-gitops integration |
| 10 | Cloud Infrastructure | Terraform/Terragrunt modules, dev/prod environments |
| 11 | Observability | OpenTelemetry instrumentation, Grafana dashboards |
| 12 | Documentation & Agent Harness | MkDocs, `.claude/`, `/.agents/*` finalization |

Phases 2–4 are largely parallelizable **per bounded context** (i.e., `users` and `tasks` domain/application/infra work can run concurrently once `shared` is stable). Phase 5 is a hard sync point — it cannot start until at least one context's infra layer exists to wire.

---

## 2. Phase Details

### Phase 1 — Foundations

**Deliverables:**
- Repo skeleton matching `project-structure.md`
- `pyproject.toml` with dependency groups (`prod`, `dev`, `lint`, `test`), ruff + ruff.lint.isort config
- `.env.example` committed (real `.env` gitignored), including Cognito-related vars:
  ```
  OWNER=local
  DEBUG=true
  LOG_LEVEL=DEBUG
  DB_*
  ATLAS_DIR
  CORS_*
  CACHE_ENABLE=true
  CACHE_NAMESPACES
  REDIS_*
  AWS_REGION
  COGNITO_USER_POOL_ID
  COGNITO_APP_CLIENT_ID
  COGNITO_DOMAIN
  ```
- `Taskfile.yml` with: `help`, `create_venv`, dependency-check guard, `linter`, `ensure_quality`, `ensure_architecture`, `unit_tests`, `remove_cache`, `coverage`, `docker:up/down/prune/shell/logs`
- `Dockerfile` (multi-stage, hot reload for dev) + `docker-compose.yml` (consistent naming, healthchecks, `depends_on: condition: service_healthy`)
- `scripts/init.sh`, `scripts/create_venv.sh`
- `.vscode/launch.json` for debugging FastAPI and pytest
- `docker/mock-data/` seeded with placeholder fixtures

**Exit criteria:** `task create_venv && task docker:up` brings up app + Postgres + Redis with healthy status; `task help` lists all commands.

---

### Phase 2 — Domain Core

**`shared` context:**
- `base_model.py`: abstract SQLAlchemy base providing `id`, `created_at`, `updated_at`, `deleted_at` (soft delete), `tenant_id`, audit fields (`created_by`, `updated_by`)
- Domain-level `value_objects/` (e.g. `Email`, `TenantId`) and `exceptions.py` (e.g. `EntityNotFoundError`, `DomainValidationError`)
- Domain `events/` base class for cross-context event publishing

**`users` context:**
- `domain/entities/user.py` — `User` aggregate (no ORM, no Pydantic — pure Python/dataclass)
- `domain/value_objects/` — e.g. `UserId`, `EmailAddress`
- `domain/repositories/` — abstract `UserRepository` port (interface only)
- `domain/services/` — domain services not naturally owned by the entity (e.g. uniqueness checks)

**`tasks` context:**
- `domain/entities/task.py` — `Task` aggregate (status, due date, owner reference via `UserId` value object — **not** a `User` entity reference, to preserve context isolation)
- `domain/repositories/` — abstract `TaskRepository` port
- `domain/events/` — `TaskCreated`, `TaskCompleted`, etc.

**Exit criteria:** `tests/unit/{users,tasks,shared}` pass against pure domain logic with zero infrastructure or framework imports (enforced by `import-linter`, configured in this phase).

---

### Phase 3 — Application Layer

For each context, implement:
- `application/commands/` — write use cases (e.g. `CreateTaskCommand`, `CompleteTaskCommand`), each taking a DTO and a repository port via constructor injection
- `application/queries/` — read use cases (e.g. `ListTasksQuery`, `GetUserByIdQuery`)
- `application/dto/` — input/output DTOs, distinct from API serializers (DTOs are the application boundary; serializers are the HTTP boundary — they should map cleanly but aren't the same objects)

**Exit criteria:** Use cases are fully unit-testable using in-memory fakes of the repository ports, with no DB or FastAPI dependency.

---

### Phase 4 — Infrastructure

**`shared`:**
- `infrastructure/db/session.py` — async session factory (asyncpg + SQLAlchemy)
- `infrastructure/cache/` — Redis client wrapper, namespace-aware (per `CACHE_NAMESPACES`)
- Atlas migration setup (`migrations/atlas.hcl`), first baseline migration

**`users`:**
- `infrastructure/db/models/` — SQLAlchemy `UserModel` extending shared `base_model`
- `infrastructure/db/repositories/` — `SqlAlchemyUserRepository` implementing the domain port
- `infrastructure/auth/` — **AWS Cognito client integration**: token verification (JWKS fetch + cache), Cognito SDK wrapper for user pool operations (sign-up/admin actions if needed), SSO callback handling
- `infrastructure/mappers/` — entity ↔ ORM model mappers

**`tasks`:**
- `infrastructure/db/models/` — `TaskModel`
- `infrastructure/db/repositories/` — `SqlAlchemyTaskRepository`
- `infrastructure/mappers/`

**Exit criteria:** Integration tests (Phase 8 groundwork) can persist and retrieve aggregates through real repository implementations against a test Postgres/SQLite instance.

---

### Phase 5 — DI Composition

- Each context gets `container.py` at its root (sibling to `domain/`, `application/`, `infrastructure/`), wiring its own use cases, repositories, and adapters as `dependency-injector` providers
- `core/di/container.py` defines `ApplicationContainer`, composing `SharedContainer`, `UsersContainer`, `TasksContainer` as sub-containers, with explicit cross-context wiring where needed (e.g. `tasks` receiving a read-only user lookup port from `users`)
- `core/config.py` (Pydantic `BaseSettings`) feeds `config = providers.Configuration()` at the root, populated from `.env`

**Exit criteria:** `ApplicationContainer()` instantiates cleanly in a script with all providers resolvable; a unit test asserts no provider is left unwired.

---

### Phase 6 — Presentation: API

- `presentation/api/app.py` — builder pattern:
  - `.mount_di_container(container)`
  - `.check_dependencies()` → backs `/health` (DB ping, Redis ping)
  - `._configure_middleware()` — CORS from `CORS_*` env vars, request logging
  - `._register_routes()` / `._register_routers()` — mounts `api/v1/users`, `api/v1/tasks`
  - `._mount_documentation()` — `/docs`, `/redoc`
  - `._create_lifespan()` — startup (DI wiring, DB pool warm-up) / shutdown (graceful connection close)
  - `.create_api()` — returns the assembled `FastAPI` instance
- `api/v1/{users,tasks}/routers.py` and `serializers.py` (Pydantic schemas mapping to/from domain entities, never DB models directly)
- `api/dependencies.py` — Cognito JWT verification dependency, authorization (role/claim checks from Cognito groups), tenant resolution
- `api/tasks.py` — FastAPI `BackgroundTasks` definitions for fire-and-forget work (e.g. notification dispatch)

**Exit criteria:** `task docker:up` exposes a working `/health`, `/docs`, and at least one authenticated CRUD flow per context, with Cognito-issued JWTs validated end-to-end.

---

### Phase 7 — Presentation: CLI

- `presentation/cli/main.py` — Typer app entrypoint
- `presentation/cli/commands/{users,tasks}.py` — admin/operational commands (e.g. `users create-admin`, `tasks purge-completed`) calling the **same** `application/` use cases as the API, via the same `ApplicationContainer`

**Exit criteria:** CLI and API never duplicate business logic — verified by both invoking identical command/query classes.

---

### Phase 8 — Testing & Governance

- `tests/unit/` — one suite per context, 100% coverage target, happy path + edge cases + errors
- `tests/integration/` — repository and DB-level tests using `pytest` + `aiosqlite`, ~10% of total test volume
- `tests/e2e/` — full API flow tests (auth → create → read → update → soft-delete), ~1% of total volume
- `tests/architecture/` — `import-linter`-backed tests asserting layer boundaries and context isolation (including the `container.py` exception rule)
- Governance pipelines added to `Taskfile`: `vulture` (dead code), `pyright` (typing), `import-linter` (boundaries)
- Coverage gate: **>97%** overall, enforced in `ensure_quality`

**Exit criteria:** `task ensure_quality && task ensure_architecture && task unit_tests && task coverage` all pass in CI with coverage ≥97%.

---

### Phase 9 — Local DevOps ("floci")

- `infra/k8s/helm/` — Helm chart: `Chart.yaml`, `values-dev.yaml`, `values-prod.yaml`, `templates/{deployment,service,job-db-init,rbac,namespace}.yaml`
- DB init as a **separate Job**, decoupled from the API `Deployment`, run via Helm hook (`pre-install`/`pre-upgrade`)
- `infra/k8s/gitops/` — integration with [local-gitops](https://github.com/cjgalvisc96/local-gitops) for local multi-cluster simulation
- Multi-cluster topology: `dev` and `prod` clusters, independent namespaces `dev-app` / `prod-app`, RBAC manifests per namespace
- `infra/tests/` — Terratest and Trivy scans for the Helm/K8s layer (the "floci" local infra unit-testing requirement)

**Exit criteria:** `helm install` succeeds against a local kind/k3d cluster wired via local-gitops, DB init Job completes before API pods report ready.

---

### Phase 10 — Cloud Infrastructure

- `infra/terraform/modules/`: `vpc`, `eks`, `ecr`, `redis`, `aurora` (public + private subnets), `route53`, `secrets-manager`, `cognito` (user pool, app client, SSO/identity provider config, RBAC via Cognito groups), `cdn`, `s3`, `eventbridge`, `sqs-sns`, `bedrock`
- `infra/terraform/environments/{dev,prod}` + `infra/terragrunt/` for DRY environment composition
- Secrets (DB credentials, Cognito client secrets) sourced from Secrets Manager, never hardcoded
- Tooling wired into CI: `terraform validate`, `Terratest`, `Trivy`, `Infracost`

**Exit criteria:** `terragrunt plan` succeeds for both `dev` and `prod` with zero `terraform validate` errors and no critical Trivy findings; Infracost report generated per PR.

---

### Phase 11 — Observability

- OpenTelemetry SDK wired into `core/telemetry.py`, instrumenting FastAPI, SQLAlchemy, Redis, and outbound Cognito calls
- OTel Collector config (`observability/otel-collector-config.yaml`) exporting traces/metrics
- Grafana dashboards (`observability/grafana/dashboards/`) for request latency, error rate, DB pool saturation, cache hit rate

**Exit criteria:** A request traced end-to-end from API → application use case → repository → DB is visible as a single trace in Grafana/Tempo.

---

### Phase 12 — Documentation & Agent Harness

- MkDocs site (`docs/`) covering architecture (link to `todo-app-architecture-summary.md`), project structure, ADRs (e.g. "Why per-context DI containers", "Why Cognito over Keycloak")
- `.claude/{skills,rules,commands}` finalized for ongoing AI-assisted development
- `/.agents/{lead,developer,architect,tester,devops,sre}` prompt/role definitions finalized, reflecting the actual repo conventions established in Phases 1–11

**Exit criteria:** A new contributor (human or agent) can onboard using only `docs/` + `.claude/` + `/.agents/*` without needing this plan as a live reference.

---

## 3. Cross-Cutting Decisions Log

Captured here so they don't get re-litigated mid-implementation:

| Decision | Rationale |
|---|---|
| DI containers live per-context, composed by a root `ApplicationContainer` | Preserves bounded context isolation; each context independently testable/extractable |
| `container.py` is a sibling to `domain/application/infrastructure/`, not nested in `infrastructure/` | Composition roots are structurally privileged — placing in `infrastructure/` would visually invert the dependency rule |
| Auth provider is **AWS Cognito only** (replacing Keycloak) | Single IdP across app-level auth and cloud infra (`infra/terraform/modules/cognito`); avoids running/maintaining a separate Keycloak deployment |
| Serializers depend on domain entities, never DB models | Decouples API contract from persistence schema changes |
| Read/write model separation (CQRS-style) | Enables independent optimization of query paths without complicating write-side invariants |
| DB init is a separate K8s Job, not part of API container startup | Avoids race conditions and repeated migration attempts across multiple API replicas |

---

## 4. Others
- Cognito:
```
  Identity
  One Cognito User Pool
      ↓
  tenant_id claim
      ↓
  Role/group claims

  Database
  Shared PostgreSQL schema
      ↓
  tenant_id on every tenant-owned table
      ↓
  PostgreSQL RLS enforcement
```
- add full IAM policies
- add another bounded context called  AI, to use a bedrock pod to interact with the IA via api in the todo app.
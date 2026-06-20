# TODO App — Implementation Plan

> Companion to `todo-app-architecture-summary.md` and `project-structure.md`. This document sequences the work into phases an agent team (or a solo dev) can execute in order, with explicit dependencies between phases.

---

## 0. Guiding Constraints

These hold across every phase and should be checked before merging any work:

- **Design principles**: follow industry standards and **SOLID, DRY, KISS, YAGNI**, applying established design patterns only where they genuinely reduce complexity or duplication. Do not add abstraction, indirection, or patterns for hypothetical future needs — unnecessary complexity and overengineering are treated as defects, not sophistication.
- **Dependency direction**: `domain → application → infrastructure`, never reversed. Only each context's `container.py` is allowed to import across all three layers.
- **Context isolation**: `users`, `tasks`, `ai`, `shared` never import each other's internals directly. Cross-context access goes through a sub-container injected at the root (`ApplicationContainer`), explicit ports, or domain events.
- **Presentation purity**: `api/` and `cli/` contain no business logic — they call `application/` use cases (commands/queries) only.
- **Serializers depend on entities, not DB models.** A DB model change must never force an API contract change without an explicit mapper update.
- **Auth provider**: **AWS Cognito** is the single source of truth for authentication (JWT) and SSO across both the application (`users/infrastructure/auth/`) and infrastructure (`infra/terraform/modules/cognito/`). No Keycloak or other IdP.
- **Tenancy enforcement**: `tenant_id` is carried as a Cognito JWT claim, bound to the DB transaction, and enforced via **PostgreSQL RLS** — never solely via application-layer `WHERE` filtering.
- **IAM**: every workload (API pod, AI pod, DB-init Job, EventBridge publisher) gets its own least-privilege role via IRSA. No shared or account-wide execution role.

---

## 1. Phase Overview

| Phase | Name | Goal |
|---|---|---|
| 1 | Foundations | Repo, tooling, env, Taskfile, Docker skeleton |
| 2 | Domain Core | `shared` kernel + base model, `users`, `tasks`, and `ai` domain layers |
| 3 | Application Layer | Use cases (commands/queries), DTOs, repository/port interfaces |
| 4 | Infrastructure | SQLAlchemy models, repos, Atlas migrations + RLS policies, Redis, Cognito client, Bedrock client |
| 5 | DI Composition | Per-context containers + root `ApplicationContainer` |
| 6 | Presentation — API | FastAPI builder, routers, serializers, middleware (incl. tenant binding), health |
| 7 | Presentation — CLI | Typer commands mirroring application use cases |
| 8 | Testing & Governance | pytest pyramid, coverage, import-linter, vulture, pyright |
| 9 | Local DevOps (floci) | Helm chart, K8s manifests (incl. IRSA service accounts), local-gitops integration |
| 10 | Cloud Infrastructure | Terraform/Terragrunt modules incl. Cognito claims Lambda + IAM roles, dev/prod environments |
| 11 | Observability | OpenTelemetry instrumentation, Grafana dashboards |
| 12 | Documentation & Agent Harness | MkDocs, `.claude/`, `/.agents/*` finalization |

Phases 2–4 are largely parallelizable **per bounded context** (i.e., `users`, `tasks`, and `ai` domain/application/infra work can run concurrently once `shared` is stable). `ai`'s application layer has a soft dependency on `tasks`' read-side DTOs once cross-context wiring is defined in Phase 5. Phase 5 is a hard sync point — it cannot start until at least one context's infra layer exists to wire.

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
  BEDROCK_MODEL_ID
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

**`ai` context:**
- `domain/entities/ai_suggestion.py` — `AiSuggestion` aggregate (prompt, response, status)
- `domain/ports/llm_client.py` — abstract `LlmClient` port (interface only, no AWS/Bedrock awareness)
- `domain/value_objects/` — e.g. `PromptText`, `ModelIdentifier`

**Exit criteria:** `tests/unit/{users,tasks,ai,shared}` pass against pure domain logic with zero infrastructure or framework imports (enforced by `import-linter`, configured in this phase).

---

### Phase 3 — Application Layer

For each context, implement:
- `application/commands/` — write use cases (e.g. `CreateTaskCommand`, `CompleteTaskCommand`, `GenerateTaskSuggestionCommand`), each taking a DTO and a repository/port via constructor injection
- `application/queries/` — read use cases (e.g. `ListTasksQuery`, `GetUserByIdQuery`)
- `application/dto/` — input/output DTOs, distinct from API serializers (DTOs are the application boundary; serializers are the HTTP boundary — they should map cleanly but aren't the same objects)
- `ai` context's `GenerateTaskSuggestionCommand` declares a constructor dependency on a `TaskReadPort` (or similar) that will be satisfied by `tasks`' read-side at the DI composition phase — not implemented yet, just the interface shape

**Exit criteria:** Use cases are fully unit-testable using in-memory fakes of the repository/port interfaces, with no DB, AWS, or FastAPI dependency.

---

### Phase 4 — Infrastructure

**`shared`:**
- `infrastructure/db/session.py` — async session factory (asyncpg + SQLAlchemy)
- `infrastructure/db/tenant_context.py` — issues `SET LOCAL app.tenant_id = '<value>'` per transaction, sourced from the bound request context
- `infrastructure/cache/` — Redis client wrapper, namespace-aware (per `CACHE_NAMESPACES`)
- Atlas migration setup (`migrations/atlas.hcl`), first baseline migration
- `migrations/policies/` — RLS policy SQL per tenant-owned table (e.g. `CREATE POLICY tenant_isolation ON tasks USING (tenant_id = current_setting('app.tenant_id')::uuid)`), applied via Atlas

**`users`:**
- `infrastructure/db/models/` — SQLAlchemy `UserModel` extending shared `base_model`
- `infrastructure/db/repositories/` — `SqlAlchemyUserRepository` implementing the domain port
- `infrastructure/auth/` — **AWS Cognito client integration**: JWT verification (JWKS fetch + cache), extraction of `tenant_id` and role/group claims, Cognito SDK wrapper for admin operations if needed
- `infrastructure/mappers/` — entity ↔ ORM model mappers

**`tasks`:**
- `infrastructure/db/models/` — `TaskModel`
- `infrastructure/db/repositories/` — `SqlAlchemyTaskRepository`
- `infrastructure/mappers/`
- `migrations/policies/tasks_rls.sql` — RLS policy scoping all reads/writes to the session's `tenant_id`

**`ai`:**
- `infrastructure/bedrock/bedrock_client.py` — implements `LlmClient` port via `boto3` Bedrock Runtime client, scoped to `BEDROCK_MODEL_ID`
- No DB model required unless suggestion history needs persistence — if so, add `infrastructure/db/models/` with the same `base_model` (tenant-isolated, RLS-covered) as every other context

**Exit criteria:** Integration tests (Phase 8 groundwork) can persist and retrieve aggregates through real repository implementations against a test Postgres instance with RLS policies active, and a query using one tenant's session variable cannot see another tenant's rows even with a permissive application-layer query.

---

### Phase 5 — DI Composition

- Each context gets `container.py` at its root (sibling to `domain/`, `application/`, `infrastructure/`), wiring its own use cases, repositories, and adapters as `dependency-injector` providers
- `core/di/container.py` defines `ApplicationContainer`, composing `SharedContainer`, `UsersContainer`, `TasksContainer`, `AiContainer` as sub-containers, with explicit cross-context wiring where needed (e.g. `tasks` receiving a read-only user lookup port from `users`; `ai` receiving a read-only task lookup port from `tasks`)
- `core/config.py` (Pydantic `BaseSettings`) feeds `config = providers.Configuration()` at the root, populated from `.env`

**Exit criteria:** `ApplicationContainer()` instantiates cleanly in a script with all providers resolvable; a unit test asserts no provider is left unwired, including the `ai → tasks` and `tasks → users` cross-context bindings.

---

### Phase 6 — Presentation: API

- `presentation/api/app.py` — builder pattern:
  - `.mount_di_container(container)`
  - `.check_dependencies()` → backs `/health` (DB ping, Redis ping)
  - `._configure_middleware()` — CORS from `CORS_*` env vars, request logging, **tenant-binding middleware** (extracts `tenant_id`/role claims from the verified JWT, binds them to the request scope ahead of any DB call)
  - `._register_routes()` / `._register_routers()` — mounts `api/v1/users`, `api/v1/tasks`, `api/v1/ai`
  - `._mount_documentation()` — `/docs`, `/redoc`
  - `._create_lifespan()` — startup (DI wiring, DB pool warm-up) / shutdown (graceful connection close)
  - `.create_api()` — returns the assembled `FastAPI` instance
- `api/v1/{users,tasks,ai}/routers.py` and `serializers.py` (Pydantic schemas mapping to/from domain entities, never DB models directly)
- `api/dependencies.py` — Cognito JWT verification dependency, authorization (role/claim checks from Cognito groups), tenant resolution feeding the tenant-binding middleware
- `api/tasks.py` — FastAPI `BackgroundTasks` definitions for fire-and-forget work (e.g. notification dispatch, async AI suggestion generation)

**Exit criteria:** `task docker:up` exposes a working `/health`, `/docs`, and at least one authenticated CRUD flow per context (including `ai`), with Cognito-issued JWTs validated end-to-end and a manual cross-tenant request verified to fail at the DB layer (RLS), not just the app layer.

---

### Phase 7 — Presentation: CLI

- `presentation/cli/main.py` — Typer app entrypoint
- `presentation/cli/commands/{users,tasks,ai}.py` — admin/operational commands (e.g. `users create-admin`, `tasks purge-completed`, `ai generate-suggestion`) calling the **same** `application/` use cases as the API, via the same `ApplicationContainer`

**Exit criteria:** CLI and API never duplicate business logic — verified by both invoking identical command/query classes.

---

### Phase 8 — Testing & Governance

- `tests/unit/` — one suite per context (`users`, `tasks`, `ai`, `shared`), 100% coverage target, happy path + edge cases + errors; `ai` uses a fake `LlmClient`, no live Bedrock
- `tests/integration/` — repository and DB-level tests using `pytest` + `aiosqlite`, ~10% of total test volume; includes a dedicated **RLS isolation test** asserting cross-tenant reads return zero rows even with unfiltered queries
- `tests/e2e/` — full API flow tests (auth → create → read → update → soft-delete), ~1% of total volume
- `tests/architecture/` — `import-linter`-backed tests asserting layer boundaries and context isolation (including the `container.py` exception rule)
- Governance pipelines added to `Taskfile`: `vulture` (dead code), `pyright` (typing), `import-linter` (boundaries)
- Coverage gate: **>97%** overall, enforced in `ensure_quality`

**Exit criteria:** `task ensure_quality && task ensure_architecture && task unit_tests && task coverage` all pass in CI with coverage ≥97%, and the RLS isolation test passes.

---

### Phase 9 — Local DevOps ("floci")

- `infra/k8s/helm/` — Helm chart: `Chart.yaml`, `values-dev.yaml`, `values-prod.yaml`, `templates/{deployment,service,job-db-init,rbac,service-account,namespace}.yaml`
- DB init as a **separate Job**, decoupled from the API `Deployment`, run via Helm hook (`pre-install`/`pre-upgrade`)
- IRSA-annotated `service-account.yaml` binding each pod to its scoped IAM role (API pod, AI/Bedrock pod, DB-init Job each get distinct service accounts)
- `infra/k8s/gitops/` — integration with [local-gitops](https://github.com/cjgalvisc96/local-gitops) for local multi-cluster simulation
- Multi-cluster topology: `dev` and `prod` clusters, independent namespaces `dev-app` / `prod-app`, K8s RBAC manifests per namespace
- `infra/tests/` — Terratest and Trivy scans for the Helm/K8s layer (the "floci" local infra unit-testing requirement)

**Exit criteria:** `helm install` succeeds against a local kind/k3d cluster wired via local-gitops, DB init Job completes before API pods report ready.

---

### Phase 10 — Cloud Infrastructure

- `infra/terraform/modules/`: `vpc`, `eks`, `ecr`, `redis`, `aurora` (public + private subnets), `route53`, `secrets-manager`, `cognito` (user pool, app client, **pre-token-generation Lambda** injecting `tenant_id` + role claims, groups for RBAC), `cdn`, `s3`, `eventbridge`, `sqs-sns`, `bedrock`, `iam`
- `infra/terraform/modules/iam/` — least-privilege roles via IRSA: API pod role (Aurora IAM auth + scoped Secrets Manager read), AI pod role (`bedrock:InvokeModel` on specific model ARNs only), DB-init Job role (DDL + secret read, no data access), EventBridge publish-only role
- `infra/terraform/environments/{dev,prod}` + `infra/terragrunt/` for DRY environment composition
- Secrets (DB credentials, Cognito client secrets) sourced from Secrets Manager, never hardcoded
- Tooling wired into CI: `terraform validate`, `Terratest`, `Trivy`, `Infracost`

**Exit criteria:** `terragrunt plan` succeeds for both `dev` and `prod` with zero `terraform validate` errors and no critical Trivy findings; Infracost report generated per PR; Trivy confirms no IAM role grants broader-than-scoped permissions.

---

### Phase 11 — Observability

- OpenTelemetry SDK wired into `core/telemetry.py`, instrumenting FastAPI, SQLAlchemy, Redis, and outbound AWS calls (Cognito, Bedrock)
- OTel Collector config (`observability/otel-collector-config.yaml`) exporting traces/metrics
- Grafana dashboards (`observability/grafana/dashboards/`) for request latency, error rate, DB pool saturation, cache hit rate

**Exit criteria:** A request traced end-to-end from API → application use case → repository → DB is visible as a single trace in Grafana/Tempo.

---

### Phase 12 — Documentation & Agent Harness

- MkDocs site (`docs/`) covering architecture (link to `todo-app-architecture-summary.md`), project structure, ADRs (e.g. "Why per-context DI containers", "Why Cognito over Keycloak", "Why RLS over app-layer tenancy", "Why AI is its own bounded context")
- `.claude/{skills,rules,commands}` finalized for ongoing AI-assisted development
- `/.agents/{lead,developer,architect,tester,devops,sre}` prompt/role definitions finalized, reflecting the actual repo conventions established in Phases 1–11

**Exit criteria:** A new contributor (human or agent) can onboard using only `docs/` + `.claude/` + `/.agents/*` without needing this plan as a live reference.

---

## 3. Cross-Cutting Decisions Log

Captured here so they don't get re-litigated mid-implementation:

| Decision | Rationale |
|---|---|
| Follow SOLID, DRY, KISS, YAGNI + appropriate design patterns, **without overengineering** | Patterns are applied only where they remove real complexity or duplication; a pattern that adds indirection without a current need is itself a violation of KISS/YAGNI. Industry standards are the baseline, not an excuse to gold-plate. |
| DI containers live per-context, composed by a root `ApplicationContainer` | Preserves bounded context isolation; each context independently testable/extractable |
| `container.py` is a sibling to `domain/application/infrastructure/`, not nested in `infrastructure/` | Composition roots are structurally privileged — placing in `infrastructure/` would visually invert the dependency rule |
| Auth provider is **AWS Cognito only** (replacing Keycloak) | Single IdP across app-level auth and cloud infra (`infra/terraform/modules/cognito`); avoids running/maintaining a separate Keycloak deployment |
| **Single Cognito User Pool**, tenancy via `tenant_id` claim (not per-tenant pools) | Multi-tenancy expressed through claims, not infrastructure duplication; far simpler to operate and scales without per-tenant provisioning (KISS) |
| **PostgreSQL RLS** is the tenancy enforcement boundary; app-layer filtering is defense-in-depth | A repository bug cannot leak cross-tenant data because the database itself rejects the rows; correctness doesn't depend on every query remembering to filter |
| **AI is its own bounded context**, depending on a `LlmClient` port | Keeps `tasks`/`users` free of LLM/AWS concerns; Bedrock can be swapped or mocked; the AWS dependency lives only in one adapter (DIP / single responsibility) |
| Serializers depend on domain entities, never DB models | Decouples API contract from persistence schema changes |
| Read/write model separation (CQRS-style) | Enables independent optimization of query paths without complicating write-side invariants |
| DB init is a separate K8s Job, not part of API container startup | Avoids race conditions and repeated migration attempts across multiple API replicas |
| **Least-privilege IAM via IRSA**, one role per workload | A compromised pod can only do what that workload needs; no shared blast radius |

---

## 4. Resolved Decisions

Previously open, now settled:

- **Cognito user pool structure** — *Resolved:* one User Pool for the whole app; `tenant_id` and role/group claims injected via a pre-token-generation Lambda. No per-tenant pools.
- **Multi-tenancy strategy** — *Resolved:* shared PostgreSQL schema with a `tenant_id` column on every tenant-owned table, enforced by RLS. Not schema-per-tenant.
- **Bedrock usage** — *Resolved:* scoped to the `ai` bounded context (e.g. task suggestions), with a dedicated IAM role limited to `bedrock:InvokeModel` on specific model ARNs.

## 5. Remaining Open Questions

- **Suggestion history persistence** — does `ai` need to store past suggestions (adding a tenant-isolated `AiSuggestionModel` + RLS policy), or are suggestions ephemeral? Decide before finalizing the `ai` infrastructure layer in Phase 4.
- **Async vs sync AI calls** — should `GenerateTaskSuggestionCommand` run inline in the request, or be dispatched as a background task / via EventBridge+SQS for longer generations? Affects whether the `ai` path needs the messaging infrastructure in Phase 4 vs Phase 10.
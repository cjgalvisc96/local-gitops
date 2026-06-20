# TODO App — Technical Design & Architecture Summary

## 1. Overview

A TODO application built with **Modular Monolithic architecture** following **Domain-Driven Design (DDD)** principles. The system is organized into clearly bounded contexts with strict separation between domain logic, presentation layers, and infrastructure concerns.

### Design Principles
The codebase follows industry standards and **SOLID, DRY, KISS, and YAGNI**, using established design patterns (builder, ports & adapters, CQRS, dependency injection) only where they genuinely reduce complexity or duplication. Abstraction is introduced to solve a present problem, never a hypothetical future one — unnecessary indirection and overengineering are treated as defects rather than sophistication.

### Bounded Contexts
- **Users** — identity, authentication, authorization
- **Tasks** — core TODO domain logic
- **AI** — Bedrock-backed AI interactions (e.g. task suggestions), isolated from `tasks`/`users` infrastructure concerns
- **Shared** — cross-cutting kernel (value objects, base entities, common utilities)

---

## 2. Engineering Workflow

Instead of a `claude/{rules,skills}` setup, the project uses a **harness engineering** approach under `/.agents/*`, with a lead agent orchestrating a multi-agent team:

- **Lead** — coordination and final decisions
- **Developer** — implementation
- **Architect** — design and DDD/architecture compliance
- **Tester** — quality assurance and test strategy
- **DevOps** — infrastructure and CI/CD
- **SRE** — reliability, observability, and operations

Guidance: rely on personal/project knowledge by default; invoke **"Think longer"** mode only for the first prompt of a session or for complex, high-impact changes.

---

## 3. Environment & Configuration

### Database Migrations
- **Atlas** for schema migrations

### Environment Variables
A `.env` file (with a corresponding `.env.example` committed to the repo) containing:

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

---

## 4. Containerization

### Dockerfile & docker-compose.yml
- Consistent naming convention across services, networks, containers, images, and volumes
- Hot reload support for local development
- Properly configured volumes
- `depends_on` with **healthcheck** conditions (not just startup order)

### Supporting Folders
- `docker/*` — mock/seed data for local environments
- `scripts/*` — bash initialization scripts

### Tooling
- **uv** for Python package/dependency management
- **VSCode debugger** configured via `.vscode/launch.json`
- **SQLAlchemy** as the ORM layer

---

## 5. Project Automation (Taskfile)

A `Taskfile` serving as the central command runner, including:

- Global variables and aliases
- Dependency checks before running commands
- A `help` command listing available tasks
- `create_venv` task for environment bootstrap

### Quality Pipelines
- `linter` — static linting
- `ensure_quality` — general quality gate
- `ensure_architecture` — DDD/architecture compliance checks
- `unit_tests` — unit test execution
- `remove_cache` — cache cleanup
- `coverage` — unit test coverage report

### Docker Tasks
- `docker:up`
- `docker:down`
- `docker:prune`
- `docker:shell`
- `docker:logs`

### Documentation
- **MkDocs** for project documentation

---

## 6. Application Architecture

### Core Libraries
- **dependency-injector** — IoC/DI container
- **Pydantic** — configuration and settings management

### FastAPI Application (Builder Pattern)

`app.py` built using a **builder pattern**, exposing methods such as:

- Mount dependency injection container
- Check application dependency connections (DB, Redis, etc.) — exposed via `/health`
- `_configure_middleware` — CORS and related middleware
- `_register_routes`
- `_register_routers`
- `_mount_documentation` — `/docs`
- `_create_lifespan` — startup and shutdown event handling
- `create_api` — final app assembly

### API Structure (`api/v1/*`)
- `api/dependencies.py` — authentication (JWT via **AWS Cognito**, with built-in **SSO**) and authorization
- `api/serializers/` — input/output schemas that depend only on **domain entities**, never on DB models directly
- `api/tasks.py` — background task definitions

### Database Models
Centralized in a **base model** to enforce consistency across the domain:
- Soft deletes (`deleted_at`)
- Audit trail
- Tenant isolation — `tenant_id` column on every tenant-owned table, **enforced at the database via PostgreSQL Row-Level Security (RLS)**, not just application-layer filtering
- Timestamps (`created_at`, `updated_at`)
- Transaction management
- **CQRS-style separation**: distinct read and write models

### Identity, Tenancy & Authorization

A single chain carries tenant and role context from login through to every query:

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

- **One Cognito User Pool** for the whole application — not per-tenant pools. Multi-tenancy is expressed via claims, not infrastructure duplication.
- A **pre-token-generation Lambda** injects a `tenant_id` custom claim and role/group claims into every issued JWT.
- The API verifies the JWT and reads `tenant_id` and role claims via `api/dependencies.py` (authentication) and a tenant-binding middleware (authorization context).
- That `tenant_id` is bound to the active database transaction (`SET LOCAL app.tenant_id = ...`), and **PostgreSQL RLS policies** — not application code — are the actual enforcement boundary: every tenant-owned table rejects rows that don't match the session's `tenant_id`, regardless of what a repository's query does or doesn't filter on.
- Role/group claims from Cognito drive authorization (permission checks), separate from the tenant isolation mechanism.

### CLI
- **Typer**-based CLI for operational/admin commands

### Data & Caching
- **asyncpg** — async PostgreSQL driver
- **Redis** — caching layer

---

## 6.1 AI Bounded Context (Amazon Bedrock)

A dedicated `ai` bounded context — peer to `users` and `tasks`, not a feature bolted onto either:

- **Domain** — defines an LLM client **port** (interface) that the domain layer depends on, with no awareness that Bedrock or AWS is the implementation. Entities such as `AiSuggestion` model the inputs/outputs of an AI interaction.
- **Application** — use cases (e.g. generating a task suggestion) that call the port, independent of how it's implemented.
- **Infrastructure** — a Bedrock adapter (via `boto3`) implementing the port, invoking a Bedrock model from within the cluster (a dedicated pod/deployment scoped to this context).
- **Cross-context access** — when a use case needs task context (e.g. "suggest a next task based on existing ones"), the `ai` context receives a read-only dependency on `tasks`, wired explicitly at the root `ApplicationContainer` — the same explicit-wiring pattern used for any other cross-context dependency.
- **Exposure** — surfaced through its own `api/v1/ai/` router and CLI command, going through the same authentication/authorization and tenant-binding path as every other request.

---

## 7. Testing

- **pytest** with **aiosqlite** for test database isolation
- Test pyramid distribution, applied per bounded context (`users`, `tasks`, `ai`, `shared`):
  - **Unit tests** — 100% coverage target
  - **Integration tests** — ~10% of suite
  - **End-to-end tests** — ~1% of suite
- Each layer covers **happy paths, edge cases, and error scenarios**
- `ai` context unit tests rely on a fake `LlmClient` port implementation — no live Bedrock calls in unit/integration tiers, only in a gated e2e/smoke suite
- Overall coverage target: **>97%**

---

## 8. Governance & Code Quality

### Pipelines
- **vulture** — dead code detection
- **pyright** — static type checking
- **import-linter** — enforce architectural boundaries via import rules

### `pyproject.toml`
- **ruff** (including `ruff.lint.isort`) for linting and import sorting
- **Dependency groups**: `prod`, `dev`, `lint`, `test`

### Presentation Layer
- Clear separation between **API** and **CLI** presentation layers

### AI/Agent Tooling
- Full `.claude/` setup (skills, rules, commands, etc.) alongside the `/.agents/*` harness

---

## 9. Infrastructure & DevOps (Local — "floci")

**Floci** (Local DevOps) — includes unit testing for infrastructure code (Terraform, etc.) and DevOps configuration (Kubernetes, etc.).

### Kubernetes
- **Helm chart** to install the application
- Dedicated **init job** to run database initialization, decoupled from the API container
- Reference implementation: [local-gitops](https://github.com/cjgalvisc96/local-gitops)
- Fully declarative setup: project, app, deployment, service, etc., all via Helm
- **Multi-cluster** topology: `dev` and `prod`
- Independent namespaces: `dev-app`, `prod-app`
- **RBAC** configuration
- DB init job remains independent from the API container/deployment

---

## 10. Cloud Infrastructure (Terraform / Terragrunt)

### Core Resources
- VPC
- EKS (Kubernetes)
- ECR (container registry)
- Redis
- Aurora (with public and private subnets)
- Route 53
- Secrets Manager
- **Cognito** — single User Pool, app client, pre-token-generation Lambda (injects `tenant_id` + role claims), groups for RBAC authorization
- CDN
- S3
- EventBridge (background/async tasks)
- SQS / SNS
- Bedrock (AI capabilities, consumed by the `ai` bounded context)

### IAM (Least Privilege via IRSA)
Every workload gets a narrowly scoped role bound to its Kubernetes ServiceAccount via IRSA — no shared or account-wide execution role:
- **API pod role** — Aurora access (IAM database authentication) and read-only access to its specific Secrets Manager secrets
- **AI pod role** — `bedrock:InvokeModel` only, scoped to specific model ARNs; no S3, no broader Bedrock permissions
- **DB-init Job role** — schema/DDL execution and Secrets Manager read only; explicitly no access to application data tables at runtime
- **EventBridge-publishing role** — publish-only permission to a specific event bus, no subscribe/manage permissions
- All roles defined as discrete Terraform modules under `infra/terraform/modules/iam/`, reviewed independently of the resources they grant access to

### Infrastructure Tooling
- **Terraform Validate** — syntax/configuration validation
- **Terratest** — automated infrastructure testing
- **Trivy** — security/vulnerability scanning
- **Infracost** — cost estimation

---

## 11. Observability

- **OpenTelemetry** for distributed tracing and metrics instrumentation
- **Grafana** for dashboards and visualization
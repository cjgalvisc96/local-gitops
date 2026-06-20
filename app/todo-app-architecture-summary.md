# TODO App — Technical Design & Architecture Summary

## 1. Overview

A TODO application built with **Modular Monolithic architecture** following **Domain-Driven Design (DDD)** principles. The system is organized into clearly bounded contexts with strict separation between domain logic, presentation layers, and infrastructure concerns.

### Bounded Contexts
- **Users** — identity, authentication, authorization
- **Tasks** — core TODO domain logic
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
- Tenant isolation
- Timestamps (`created_at`, `updated_at`)
- Transaction management
- **CQRS-style separation**: distinct read and write models

### CLI
- **Typer**-based CLI for operational/admin commands

### Data & Caching
- **asyncpg** — async PostgreSQL driver
- **Redis** — caching layer

---

## 7. Testing

- **pytest** with **aiosqlite** for test database isolation
- Test pyramid distribution:
  - **Unit tests** — 100% coverage target
  - **Integration tests** — ~10% of suite
  - **End-to-end tests** — ~1% of suite
- Each layer covers **happy paths, edge cases, and error scenarios**
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
- Cognito (SSO authentication and RBAC authorization)
- CDN
- S3
- EventBridge (background/async tasks)
- SQS / SNS
- Bedrock (AI capabilities)

### Infrastructure Tooling
- **Terraform Validate** — syntax/configuration validation
- **Terratest** — automated infrastructure testing
- **Trivy** — security/vulnerability scanning
- **Infracost** — cost estimation

---

## 11. Observability

- **OpenTelemetry** for distributed tracing and metrics instrumentation
- **Grafana** for dashboards and visualization
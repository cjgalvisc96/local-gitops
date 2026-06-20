# TODO App — Project Structure

```
todo-app/
├── .agents/                          # Harness engineering (multi-agent setup)
│   ├── lead/
│   ├── developer/
│   ├── architect/
│   ├── tester/
│   ├── devops/
│   └── sre/
│
├── .claude/                          # Claude skills, rules, commands
│   ├── skills/
│   ├── rules/
│   └── commands/
│
├── .vscode/
│   └── launch.json                   # Debugger config
│
├── src/
│   └── todo_app/
│       ├── contexts/                 # Bounded contexts (DDD)
│       │   │
│       │   ├── shared/                       # Shared Kernel
│       │   │   ├── domain/
│       │   │   │   ├── entities/
│       │   │   │   ├── value_objects/
│       │   │   │   ├── events/
│       │   │   │   └── exceptions.py
│       │   │   ├── application/
│       │   │   ├── infrastructure/
│       │   │   │   ├── db/
│       │   │   │   │   ├── base_model.py    # soft delete, audit, tenant, timestamps
│       │   │   │   │   ├── session.py
│       │   │   │   │   └── tenant_context.py # sets app.tenant_id for RLS per request/tx
│       │   │   │   ├── cache/               # Redis
│       │   │   │   └── messaging/
│       │   │   └── container.py             # SharedContainer (composition root)
│       │   │
│       │   ├── users/                        # Users bounded context
│       │   │   ├── domain/
│       │   │   │   ├── entities/
│       │   │   │   │   └── user.py
│       │   │   │   ├── value_objects/
│       │   │   │   ├── repositories/         # interfaces (ports)
│       │   │   │   ├── services/
│       │   │   │   └── events/
│       │   │   ├── application/
│       │   │   │   ├── commands/             # write use cases
│       │   │   │   ├── queries/              # read use cases
│       │   │   │   └── dto/
│       │   │   ├── infrastructure/
│       │   │   │   ├── db/
│       │   │   │   │   ├── models/           # SQLAlchemy models
│       │   │   │   │   └── repositories/     # repo implementations
│       │   │   │   ├── auth/                 # AWS Cognito/JWT integration
│       │   │   │   └── mappers/
│       │   │   └── container.py              # UsersContainer (composition root)
│       │   │
│       │   ├── tasks/                        # Tasks bounded context
│       │   │   ├── domain/
│       │   │   │   ├── entities/
│       │   │   │   │   └── task.py
│       │   │   │   ├── value_objects/
│       │   │   │   ├── repositories/
│       │   │   │   ├── services/
│       │   │   │   └── events/
│       │   │   ├── application/
│       │   │   │   ├── commands/
│       │   │   │   ├── queries/
│       │   │   │   └── dto/
│       │   │   ├── infrastructure/
│       │   │   │   ├── db/
│       │   │   │   │   ├── models/
│       │   │   │   │   └── repositories/
│       │   │   │   └── mappers/
│       │   │   └── container.py              # TasksContainer (composition root)
│       │   │
│       │   └── ai/                           # AI bounded context
│       │       ├── domain/
│       │       │   ├── entities/
│       │       │   │   └── ai_suggestion.py
│       │       │   ├── value_objects/
│       │       │   ├── ports/                # LLM client port (interface, AWS-agnostic)
│       │       │   │   └── llm_client.py
│       │       │   └── events/
│       │       ├── application/
│       │       │   ├── commands/             # e.g. GenerateTaskSuggestionCommand
│       │       │   ├── queries/
│       │       │   └── dto/
│       │       ├── infrastructure/
│       │       │   ├── bedrock/
│       │       │   │   └── bedrock_client.py # implements llm_client port via boto3
│       │       │   └── mappers/
│       │       └── container.py              # AiContainer (composition root)
│       │
│       ├── presentation/             # Presentation layer (separated per channel)
│       │   ├── api/
│       │   │   ├── v1/
│       │   │   │   ├── users/
│       │   │   │   │   ├── routers.py
│       │   │   │   │   └── serializers.py    # input/output (entity-based, not DB models)
│       │   │   │   ├── tasks/
│       │   │   │   │   ├── routers.py
│       │   │   │   │   └── serializers.py
│       │   │   │   └── ai/
│       │   │   │       ├── routers.py
│       │   │   │       └── serializers.py
│       │   │   ├── dependencies.py           # auth (JWT via AWS Cognito, SSO), authorization
│       │   │   ├── tasks.py                  # background tasks
│       │   │   ├── middleware/
│       │   │   │   └── tenant_middleware.py  # extracts tenant_id claim, binds RLS session var
│       │   │   └── app.py                    # Builder pattern entrypoint
│       │   │
│       │   └── cli/
│       │       ├── commands/
│       │       │   ├── users.py
│       │       │   ├── tasks.py
│       │       │   └── ai.py
│       │       └── main.py                   # Typer entrypoint
│       │
│       ├── core/
│       │   ├── config.py             # Pydantic settings
│       │   ├── di/
│       │   │   └── container.py      # ApplicationContainer — composes shared/users/tasks/ai
│       │   ├── logging.py
│       │   └── telemetry.py          # OpenTelemetry setup
│       │
│       └── main.py                   # App bootstrap
│
├── tests/
│   ├── unit/
│   │   ├── users/
│   │   ├── tasks/
│   │   ├── ai/
│   │   └── shared/
│   ├── integration/
│   │   ├── users/
│   │   ├── tasks/
│   │   └── ai/
│   ├── e2e/
│   ├── architecture/                 # import-linter / DDD boundary tests
│   └── conftest.py
│
├── migrations/                       # Atlas migrations
│   ├── atlas.hcl
│   ├── versions/
│   └── policies/                     # PostgreSQL RLS policy definitions per tenant-owned table
│       ├── users_rls.sql
│       └── tasks_rls.sql
│
├── docker/
│   ├── mock-data/                    # Seed/mock data
│   └── init/                         # DB init helpers
│
├── scripts/
│   ├── init.sh
│   └── create_venv.sh
│
├── docs/                             # MkDocs source
│   ├── index.md
│   └── architecture/
│
├── infra/
│   ├── k8s/
│   │   ├── helm/
│   │   │   ├── Chart.yaml
│   │   │   ├── values-dev.yaml
│   │   │   ├── values-prod.yaml
│   │   │   └── templates/
│   │   │       ├── deployment.yaml
│   │   │       ├── service.yaml
│   │   │       ├── job-db-init.yaml   # independent DB init job
│   │   │       ├── rbac.yaml          # K8s RBAC (cluster-internal)
│   │   │       ├── service-account.yaml # IRSA-annotated SA, binds pod to IAM role
│   │   │       └── namespace.yaml
│   │   └── gitops/                    # local-gitops integration
│   │
│   ├── terraform/
│   │   ├── modules/
│   │   │   ├── vpc/
│   │   │   ├── eks/
│   │   │   ├── ecr/
│   │   │   ├── redis/
│   │   │   ├── aurora/
│   │   │   ├── route53/
│   │   │   ├── secrets-manager/
│   │   │   ├── cognito/
│   │   │   │   ├── main.tf                  # user pool, app client, RLS-relevant attrs
│   │   │   │   ├── groups.tf                # RBAC groups (roles) per tenant/permission tier
│   │   │   │   └── pre_token_lambda/        # injects tenant_id + role claims into JWT
│   │   │   ├── cdn/
│   │   │   ├── s3/
│   │   │   ├── eventbridge/
│   │   │   ├── sqs-sns/
│   │   │   ├── bedrock/
│   │   │   └── iam/                         # least-privilege IAM roles/policies (IRSA)
│   │   │       ├── api_pod_role.tf          # DB (IAM auth) + Secrets Manager read
│   │   │       ├── ai_pod_role.tf           # bedrock:InvokeModel only, scoped to model ARNs
│   │   │       ├── db_init_job_role.tf      # migrations: DDL + Secrets Manager read only
│   │   │       └── eventbridge_role.tf      # publish-only to specific event bus
│   │   └── environments/
│   │       ├── dev/
│   │       └── prod/
│   │
│   ├── terragrunt/
│   │   ├── terragrunt.hcl
│   │   ├── dev/
│   │   └── prod/
│   │
│   └── tests/                        # floci: infra unit tests
│       ├── terratest/
│       └── trivy/
│
├── observability/
│   ├── otel-collector-config.yaml
│   └── grafana/
│       └── dashboards/
│
├── .env
├── .env.example
├── Dockerfile
├── docker-compose.yml
├── Taskfile.yml
├── pyproject.toml
├── uv.lock
└── README.md
```

## Key Structural Principles

**Design principles first** — the whole structure serves SOLID, DRY, KISS, and YAGNI. Layers, ports, and per-context containers exist because they remove real coupling and duplication, not for their own sake. Where a simpler arrangement would do the same job, it wins; no pattern is added for a problem the codebase doesn't yet have. Overengineering is a defect.

**Bounded context isolation** — each context (`users`, `tasks`, `ai`, `shared`) owns its full vertical slice: `domain/ → application/ → infrastructure/`. No context imports another context's internals directly; cross-context communication goes through domain events, explicit ports, or the shared kernel.

**Dependency direction** — `domain/` has zero framework dependencies. `application/` depends only on `domain/`. `infrastructure/` implements `domain/` repository/port interfaces. `presentation/` depends on `application/`, never directly on `infrastructure/` or DB models.

**DI as composition root, not infrastructure** — each context's `container.py` sits as a sibling to `domain/`, `application/`, and `infrastructure/`, not nested inside any of them. A composition root is structurally privileged: it's the only thing allowed to "see" and wire all three layers at once. Placing it inside `infrastructure/` would visually imply `application` depends on `infrastructure`, which inverts the actual dependency rule. Keeping it as a sibling makes that asymmetry explicit instead of hidden.

**Two-tier DI composition** — every context owns its own `Container` (e.g. `UsersContainer`, `TasksContainer`, `AiContainer`, `SharedContainer`), independently instantiable and testable. `core/di/container.py` holds a single `ApplicationContainer` that imports each context's container as a `providers.Container(...)` sub-container and wires cross-context dependencies explicitly:

```python
# core/di/container.py
from dependency_injector import containers, providers

from todo_app.contexts.shared.container import SharedContainer
from todo_app.contexts.users.container import UsersContainer
from todo_app.contexts.tasks.container import TasksContainer
from todo_app.contexts.ai.container import AiContainer


class ApplicationContainer(containers.DeclarativeContainer):
    config = providers.Configuration()

    shared = providers.Container(SharedContainer, config=config)
    users = providers.Container(UsersContainer, config=config, shared=shared)
    tasks = providers.Container(
        TasksContainer, config=config, shared=shared, users=users
    )
    ai = providers.Container(
        AiContainer, config=config, shared=shared, tasks=tasks
    )
```

Any cross-context dependency (e.g. `tasks` needing a read-only `UserRepository` port from `users`, or `ai` needing a read-only task lookup from `tasks` to generate suggestions) is passed explicitly as a sub-container argument at the root — making coupling between contexts visible and reviewable, rather than implicit in a single flat container.

**Multi-tenancy: claims → session var → RLS** — tenancy is enforced at three layers, not just one:
1. **Identity** — a single Cognito User Pool issues JWTs carrying a `tenant_id` custom claim and role/group claims, injected at token-mint time via a pre-token-generation Lambda (`infra/terraform/modules/cognito/pre_token_lambda/`).
2. **Application** — `presentation/api/middleware/tenant_middleware.py` extracts `tenant_id` from the verified JWT and binds it to the current request/transaction scope.
3. **Database** — `shared/infrastructure/db/tenant_context.py` issues `SET LOCAL app.tenant_id = '<value>'` at the start of each transaction; PostgreSQL **Row-Level Security** policies (`migrations/policies/*.sql`) compare `tenant_id` against `current_setting('app.tenant_id')` on every tenant-owned table.

The application layer is **not** the tenancy enforcement boundary — it's RLS. App-layer filtering by `tenant_id` is defense-in-depth, not the source of truth; a bug in a repository's `WHERE` clause cannot leak cross-tenant data because the database itself refuses the rows.

**AI as a peer bounded context, not a `tasks` feature** — `ai` has its own domain (a `BedrockClient` port the domain layer is unaware is AWS-specific), its own use cases, and its own infrastructure adapter (`infrastructure/bedrock/`). This keeps `tasks` free of any LLM/AWS concerns and lets the Bedrock integration evolve, get swapped, or get mocked in tests independently. Its dependency on `tasks` (e.g. to read task context for a suggestion) is wired explicitly at the `ApplicationContainer`, the same pattern used for `tasks → users`.

**IAM follows least privilege via IRSA** — each workload gets its own scoped IAM role bound through a Kubernetes ServiceAccount (IRSA), defined under `infra/terraform/modules/iam/`: the API pod's role can reach the DB and read app secrets; the `ai` pod's role can only call `bedrock:InvokeModel` against specific model ARNs; the DB-init Job's role is limited to DDL execution and has no runtime data access; nothing gets a broad account-wide policy.

**Presentation separation** — `api/` and `cli/` are siblings under `presentation/`, both consuming the same `application/` layer (via the `ApplicationContainer`), enforcing that business logic never lives in a router or CLI command.

**Architecture enforcement** — `import-linter` rules (configured in `pyproject.toml`) and `tests/architecture/` programmatically verify these boundaries aren't violated as the codebase grows, including that only `container.py` files are permitted to import across all three layers of a context.

**Infra as a peer concern** — `infra/` mirrors the same maturity as `src/`: Helm for K8s, Terraform/Terragrunt for cloud, with dedicated `infra/tests/` for Terratest and Trivy scans (the "floci" local DevOps testing layer).
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
│       │   │   │   │   └── session.py
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
│       │   └── tasks/                        # Tasks bounded context
│       │       ├── domain/
│       │       │   ├── entities/
│       │       │   │   └── task.py
│       │       │   ├── value_objects/
│       │       │   ├── repositories/
│       │       │   ├── services/
│       │       │   └── events/
│       │       ├── application/
│       │       │   ├── commands/
│       │       │   ├── queries/
│       │       │   └── dto/
│       │       ├── infrastructure/
│       │       │   ├── db/
│       │       │   │   ├── models/
│       │       │   │   └── repositories/
│       │       │   └── mappers/
│       │       └── container.py              # TasksContainer (composition root)
│       │
│       ├── presentation/             # Presentation layer (separated per channel)
│       │   ├── api/
│       │   │   ├── v1/
│       │   │   │   ├── users/
│       │   │   │   │   ├── routers.py
│       │   │   │   │   └── serializers.py    # input/output (entity-based, not DB models)
│       │   │   │   └── tasks/
│       │   │   │       ├── routers.py
│       │   │   │       └── serializers.py
│       │   │   ├── dependencies.py           # auth (JWT via AWS Cognito, SSO), authorization
│       │   │   ├── tasks.py                  # background tasks
│       │   │   ├── middleware/
│       │   │   └── app.py                    # Builder pattern entrypoint
│       │   │
│       │   └── cli/
│       │       ├── commands/
│       │       │   ├── users.py
│       │       │   └── tasks.py
│       │       └── main.py                   # Typer entrypoint
│       │
│       ├── core/
│       │   ├── config.py             # Pydantic settings
│       │   ├── di/
│       │   │   └── container.py      # ApplicationContainer — composes shared/users/tasks
│       │   ├── logging.py
│       │   └── telemetry.py          # OpenTelemetry setup
│       │
│       └── main.py                   # App bootstrap
│
├── tests/
│   ├── unit/
│   │   ├── users/
│   │   ├── tasks/
│   │   └── shared/
│   ├── integration/
│   │   ├── users/
│   │   └── tasks/
│   ├── e2e/
│   ├── architecture/                 # import-linter / DDD boundary tests
│   └── conftest.py
│
├── migrations/                       # Atlas migrations
│   ├── atlas.hcl
│   └── versions/
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
│   │   │       ├── rbac.yaml
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
│   │   │   ├── cdn/
│   │   │   ├── s3/
│   │   │   ├── eventbridge/
│   │   │   ├── sqs-sns/
│   │   │   └── bedrock/
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

**Bounded context isolation** — each context (`users`, `tasks`, `shared`) owns its full vertical slice: `domain/ → application/ → infrastructure/`. No context imports another context's internals directly; cross-context communication goes through domain events or the shared kernel.

**Dependency direction** — `domain/` has zero framework dependencies. `application/` depends only on `domain/`. `infrastructure/` implements `domain/` repository interfaces. `presentation/` depends on `application/`, never directly on `infrastructure/` or DB models.

**DI as composition root, not infrastructure** — each context's `container.py` sits as a sibling to `domain/`, `application/`, and `infrastructure/`, not nested inside any of them. A composition root is structurally privileged: it's the only thing allowed to "see" and wire all three layers at once. Placing it inside `infrastructure/` would visually imply `application` depends on `infrastructure`, which inverts the actual dependency rule. Keeping it as a sibling makes that asymmetry explicit instead of hidden.

**Two-tier DI composition** — every context owns its own `Container` (e.g. `UsersContainer`, `TasksContainer`, `SharedContainer`), independently instantiable and testable. `core/di/container.py` holds a single `ApplicationContainer` that imports each context's container as a `providers.Container(...)` sub-container and wires cross-context dependencies explicitly:

```python
# core/di/container.py
from dependency_injector import containers, providers

from todo_app.contexts.shared.container import SharedContainer
from todo_app.contexts.users.container import UsersContainer
from todo_app.contexts.tasks.container import TasksContainer


class ApplicationContainer(containers.DeclarativeContainer):
    config = providers.Configuration()

    shared = providers.Container(SharedContainer, config=config)
    users = providers.Container(UsersContainer, config=config, shared=shared)
    tasks = providers.Container(
        TasksContainer, config=config, shared=shared, users=users
    )
```

Any cross-context dependency (e.g. `tasks` needing a read-only `UserRepository` port from `users`) is passed explicitly as a sub-container argument at the root — making coupling between contexts visible and reviewable, rather than implicit in a single flat container.

**Presentation separation** — `api/` and `cli/` are siblings under `presentation/`, both consuming the same `application/` layer (via the `ApplicationContainer`), enforcing that business logic never lives in a router or CLI command.

**Architecture enforcement** — `import-linter` rules (configured in `pyproject.toml`) and `tests/architecture/` programmatically verify these boundaries aren't violated as the codebase grows, including that only `container.py` files are permitted to import across all three layers of a context.

**Infra as a peer concern** — `infra/` mirrors the same maturity as `src/`: Helm for K8s, Terraform/Terragrunt for cloud, with dedicated `infra/tests/` for Terratest and Trivy scans (the "floci" local DevOps testing layer).
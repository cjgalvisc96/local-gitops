# Copier Template Plan — `copier-todo-ddd`

> A plan for turning the full TODO app (see `plan.md`, `project-structure.md`, `todo-app-architecture-summary.md`) into a modern, production-ready [Copier](https://copier.readthedocs.io/en/stable/) template that scaffolds a new project from answers and supports safe updates over time.
>
> This document describes **how to build the template**, not the rendered application. It targets Copier ≥ 9 conventions (`.jinja` suffix, `_subdirectory`, `_tasks`, `when` conditionals, answers-file updates).

---

## 0. Design Principles for the Template Itself

The same principles the app follows (SOLID, DRY, KISS, YAGNI) apply to the template:

- **KISS / YAGNI** — every question must change the generated output in a way the user actually needs. A toggle nobody flips is dead weight; prefer a sensible default and let advanced users edit post-generation. Resist adding questions for hypothetical variations.
- **DRY** — derived values (slugs, module names, image names) are computed once via Jinja includes/macros, never re-asked.
- **Update-safe** — the template is a Git repo with tags; the rendered project keeps a `.copier-answers.yml` so `copier update` works. Anything generated *once* and never re-touched (secrets, sample data) is handled via `_skip_if_exists` or `_exclude` with `_copier_operation`.
- **Fail loud** — `_envops.undefined = jinja2.StrictUndefined` so a missing variable breaks generation instead of silently emitting blanks.

---

## 1. Template Repository Layout

One template = one Git repo (Copier's recommendation, required for updates). Metadata lives at the root; the renderable tree lives under `template/` via `_subdirectory`.

```
copier-todo-ddd/                          # the TEMPLATE repo (not the generated app)
├── copier.yml                            # questionnaire + settings
├── README.md                             # how to use the template
├── CHANGELOG.md                          # template version history (drives updates)
├── LICENSE
├── .gitignore                            # ignore rules for the TEMPLATE repo
├── includes/                             # Jinja macros/partials (excluded from render)
│   ├── slugify.jinja
│   ├── module-name.jinja
│   └── docker-image-name.jinja
├── tasks/                                # post-generation helper scripts invoked by _tasks
│   ├── post_gen.py
│   └── check_tools.sh
├── tests/                                # template tests (pytest + copier API)
│   ├── test_generation.py               # render with various answer combos, assert files
│   ├── test_lint_clean.py               # generated project passes its own ruff/pyright
│   └── matrix.yml                        # answer combinations to test
└── template/                             # _subdirectory — the actual app tree
    ├── {{ _copier_conf.answers_file }}.jinja
    ├── pyproject.toml.jinja
    ├── README.md.jinja
    ├── .env.example.jinja
    ├── Taskfile.yml.jinja
    ├── Dockerfile.jinja
    ├── docker-compose.yml.jinja
    ├── .vscode/launch.json.jinja
    ├── src/{{ module_name }}/ ...        # full DDD tree from project-structure.md
    ├── tests/ ...
    ├── migrations/ ...
    ├── docker/ ...
    ├── scripts/ ...
    ├── docs/ ...
    ├── observability/ ...
    ├── {% if include_k8s %}infra/k8s{% endif %}/ ...
    ├── {% if include_terraform %}infra/terraform{% endif %}/ ...
    ├── {% if include_terraform %}infra/terragrunt{% endif %}/ ...
    ├── {% if include_agents %}.agents{% endif %}/ ...
    └── {% if include_claude %}.claude{% endif %}/ ...
```

Key mechanics:
- `_subdirectory: template` keeps the questionnaire and template-repo dotfiles separate from the generated project's dotfiles.
- `includes/` and `tasks/` are listed in `_exclude` so they never land in the generated project.
- Conditional **directories** use `{% if flag %}dir{% endif %}` and must **not** carry the `.jinja` suffix (Copier rule). Conditional **files** put the condition outside the suffix: `{% if flag %}file.ext{% endif %}.jinja`.

---

## 2. Questionnaire Design (`copier.yml`)

Questions are grouped: identity, architecture toggles, infrastructure toggles, AI, tooling. Defaults reflect the reference design so a user can press Enter through everything and get the full app.

### 2.1 Project identity

| Question | Type | Default | Notes |
|---|---|---|---|
| `project_name` | str | — (required) | Human-readable. Validated: must be non-empty. |
| `project_slug` | str | derived from `project_name` | `default` via `{% include 'slugify.jinja' %}`; validated against `^[a-z][a-z0-9-]+$`. |
| `module_name` | str | derived from slug | Python package name (`todo_app`-style); `slug` with dashes→underscores. |
| `author_name` | str | — | |
| `author_email` | str | — | Validated as an email. |
| `python_version` | str (choices) | `3.12` | `3.11` / `3.12` / `3.13`; feeds `pyproject.toml` and Docker base image. |
| `owner` | str | `local` | Maps to `OWNER` env var. |

`project_slug` and `module_name` are **derived defaults**, not separate manual entry — DRY. The user can still override at the prompt.

### 2.2 Bounded contexts

| Question | Type | Default | Notes |
|---|---|---|---|
| `bounded_contexts` | multiselect | `[users, tasks, ai]` | `users` and `tasks` are effectively mandatory; `shared` is always generated and not offered as a choice. `ai` is opt-out. |
| `include_ai` | bool (computed) | `{{ 'ai' in bounded_contexts }}` | `when: false` — a computed value, not asked. Drives the whole `ai` context + Bedrock module + AI IAM role. |

Using a computed `include_ai` keeps every downstream `{% if include_ai %}` clean instead of repeating the membership test.

### 2.3 Auth & multi-tenancy

| Question | Type | Default | Notes |
|---|---|---|---|
| `auth_provider` | str (choices) | `cognito` | Only `cognito` for now (matches the design). Modeled as a choice so a future `none`/other option is a non-breaking addition. |
| `enable_rls` | bool | `true` | When true, generates `migrations/policies/*.sql`, the tenant-context session hook, and the tenant middleware. Off → single-tenant scaffold without RLS. |
| `tenant_strategy` | str (choices) | `shared_schema_rls` | `shared_schema_rls` only, gated on `enable_rls`. `when: "{{ enable_rls }}"`. |

### 2.4 Infrastructure toggles

| Question | Type | Default | Notes |
|---|---|---|---|
| `include_docker` | bool | `true` | Dockerfile + compose + `docker:*` Taskfile targets. |
| `include_k8s` | bool | `true` | Helm chart + local-gitops wiring + IRSA service accounts. |
| `include_terraform` | bool | `true` | Terraform modules + Terragrunt envs. |
| `cloud_modules` | multiselect | all | `when: "{{ include_terraform }}"`. Choices: `vpc, eks, ecr, redis, aurora, route53, secrets_manager, cognito, cdn, s3, eventbridge, sqs_sns, bedrock, iam`. `bedrock` choice is **disabled via validator** when `include_ai` is false (`{% if not include_ai %}Requires the AI context{% endif %}`). |
| `include_observability` | bool | `true` | OpenTelemetry wiring + Grafana dashboards. |

### 2.5 Tooling & governance

| Question | Type | Default | Notes |
|---|---|---|---|
| `package_manager` | str (choices) | `uv` | `uv` only for now; modeled as choice for forward-compat. |
| `include_governance` | bool | `true` | vulture + pyright + import-linter config and Taskfile targets. |
| `coverage_threshold` | int | `97` | Validated 0–100; written into `pyproject.toml`/CI. |
| `include_cli` | bool | `true` | Typer presentation layer. |
| `include_mkdocs` | bool | `true` | Docs site. |
| `include_agents` | bool | `true` | `/.agents/*` harness. |
| `include_claude` | bool | `true` | `.claude/{skills,rules,commands}`. |
| `license` | str (choices) | `MIT` | `MIT / Apache-2.0 / Proprietary`; drives `LICENSE`. |

### 2.6 Secrets (not recorded)

Marked under `_secret_questions` so they are prompted with masking and **never written to `.copier-answers.yml`**:

- `cognito_app_client_secret` — optional, defaulted empty; only used to seed a Git-ignored local `.env` (never `.env.example`).

Secrets get a required default (Copier requires this) of `""` and are written only into files matched by `_skip_if_exists` so an update never clobbers a real local secret.

---

## 3. Settings Block (`copier.yml` `_`-prefixed keys)

```yaml
_min_copier_version: "9.0.0"
_subdirectory: template
_templates_suffix: .jinja
_envops:
  undefined: jinja2.StrictUndefined        # fail on missing vars
_answers_file: .copier-answers.yml
_exclude:
  - includes
  - tasks
  - tests
  - "copier.yml"
  - "*.pyc"
  - "__pycache__"
  - ".git"
_skip_if_exists:
  - .env                                   # never overwrite a real local env on update
  - .secrets.yaml
_jinja_extensions:
  - copier_templates_extensions.TemplateExtensionLoader   # context hooks for derived values
  - jinja2_time.TimeExtension                             # {% now %} for generated-on stamps
_message_before_copy: |
  Scaffolding your DDD modular-monolith TODO service.
  Press Enter to accept defaults (full reference architecture).
_message_after_copy: |
  ✅ Project "{{ project_name }}" generated.

  Next:
    cd {{ _copier_conf.dst_path }}
    task create_venv
    task docker:up        {% if not include_docker %}# (docker disabled){% endif %}
    task help
```

`_jinja_extensions` must be installed alongside Copier (`uv tool install --with copier-templates-extensions --with jinja2-time copier`); the README documents this. Because extensions + tasks are used, the template is **unsafe** by Copier's definition and consumers must pass `--trust` — the README states this explicitly.

---

## 4. Post-Generation Automation (`_tasks`)

Run after rendering, ordered, each in its own subprocess. Guarded with `when` so they only run on first `copy`, not on `update`, and only when the relevant tool is selected.

```yaml
_tasks:
  # 1. Initialize a git repo so the project is immediately update-able
  - command: "git init -q"
    when: "{{ _copier_operation == 'copy' }}"

  # 2. Verify required tooling exists before bootstrapping (KISS guard, mirrors the
  #    Taskfile's "check dependencies before commands" requirement)
  - command: ["bash", "tasks/check_tools.sh"]
    when: "{{ _copier_operation == 'copy' }}"
    working_directory: "{{ _copier_conf.src_path }}"

  # 3. Create the venv + sync deps with uv
  - command: "uv venv && uv sync"
    when: "{{ _copier_operation == 'copy' and package_manager == 'uv' }}"

  # 4. Run the project's own architecture/lint gates so it's born green
  - command: "uv run task ensure_architecture"
    when: "{{ _copier_operation == 'copy' and include_governance }}"

  # 5. Initial commit so `copier update` has a baseline
  - command: "git add -A && git commit -q -m 'chore: initial scaffold from copier-todo-ddd'"
    when: "{{ _copier_operation == 'copy' }}"
```

`tasks/check_tools.sh` checks for `uv`, plus `docker`, `helm`, `terraform`, `kubectl` **only when the matching toggle is on** — it reads the rendered `.copier-answers.yml` to know which were selected, so the check stays in sync with the answers without duplicating the conditionals.

---

## 5. Derived Values via Jinja Includes

Computed once, reused everywhere (DRY). Stored in `includes/` (excluded from output).

`includes/slugify.jinja`:
```jinja
{{ project_name | lower | replace(' ', '-') | regex_replace('[^a-z0-9-]', '') }}
```

`includes/module-name.jinja`:
```jinja
{{ project_slug | replace('-', '_') }}
```

`includes/docker-image-name.jinja`:
```jinja
{{ owner }}/{{ project_slug }}
```

Used in `copier.yml` as default values, e.g.:
```yaml
project_slug:
  type: str
  default: "{% include 'slugify.jinja' %}"
  validator: >-
    {% if not (project_slug | regex_search('^[a-z][a-z0-9-]+$')) %}
    Use lowercase letters, digits and dashes; start with a letter.
    {% endif %}

module_name:
  type: str
  default: "{% include 'module-name.jinja' %}"
```

The same image-name partial feeds `docker-compose.yml.jinja`, the Helm `values-*.yaml.jinja`, and the ECR module so "consistent naming across services, networks, containers, images, volumes" (a hard requirement from the brief) is enforced from a single source.

---

## 6. Mapping App Features → Template Conditionals

How each toggle prunes or includes parts of the tree from `project-structure.md`:

| Answer | Includes / Excludes |
|---|---|
| `include_ai = false` | Drops `src/{{ module_name }}/contexts/ai/`, `api/v1/ai/`, `cli/commands/ai.py`, `tests/{unit,integration}/ai/`, the `bedrock` Terraform module, the AI IAM role, and removes the `ai` sub-container wiring from `core/di/container.py.jinja`. |
| `enable_rls = false` | Drops `migrations/policies/`, `shared/.../db/tenant_context.py`, and `api/middleware/tenant_middleware.py`; base model keeps `tenant_id` column but without RLS policies. |
| `include_k8s = false` | Drops `infra/k8s/` entirely and the K8s rows from `infra/tests/`. |
| `include_terraform = false` | Drops `infra/terraform/` + `infra/terragrunt/`; `cloud_modules` question is skipped (`when`). |
| `cloud_modules` subset | Each `infra/terraform/modules/<m>/` dir is wrapped in `{% if 'm' in cloud_modules %}`. |
| `include_cli = false` | Drops `presentation/cli/`; Typer removed from `pyproject.toml` deps. |
| `include_observability = false` | Drops `observability/` and OTel wiring in `core/telemetry.py`. |
| `include_agents / include_claude = false` | Drops `.agents/` / `.claude/` respectively. |

The DI container, `pyproject.toml` dependency groups, and the Taskfile targets are all templated so that disabling a feature also removes its dependencies and its commands — no dangling imports or dead tasks (avoids the overengineering smell of shipping config for things that aren't there).

---

## 7. Template Testing Strategy

The template ships its own `tests/` (excluded from generated output), run in the template repo's CI:

- **Generation matrix** (`tests/test_generation.py`) — uses Copier's Python API (`copier.run_copy`) to render the template across answer combinations from `tests/matrix.yml`: full build; `include_ai=false`; `include_terraform=false`; minimal (most toggles off). Each asserts the expected files exist/don't exist.
- **Born-green check** (`tests/test_lint_clean.py`) — for the full-build render, run the generated project's own `ruff`, `pyright`, and `import-linter` and assert zero findings. This guarantees the template emits a project that immediately passes its own gates.
- **Update smoke test** — render at tag `vN`, commit, then `copier update` to `vN+1` against a trivial change and assert no crash and a clean merge.
- **CI** — GitHub Actions matrix over `python_version` choices; `copier` invoked with `--trust` (extensions/tasks are present).

---

## 8. Versioning & Updates

- Template is tagged with **SemVer** Git tags; Copier copies the latest release by default and uses tags to compute update diffs.
- `CHANGELOG.md` documents each release; breaking template changes (renamed questions, restructured dirs) bump the major and get a `_migrations` entry.
- **Migrations** (`_migrations`) handle answer/structure evolution, e.g. if `bounded_contexts` replaces an older `include_ai` boolean:
  ```yaml
  _migrations:
    - version: v2.0.0
      command: "{{ _copier_python }} tasks/post_gen.py migrate-contexts"
      when: "{{ _stage == 'before' }}"
  ```
- Because answers persist in `.copier-answers.yml`, consumers run `copier update` to pull template improvements (new lint rules, security fixes, dependency bumps) while keeping their own code and answers.

---

## 9. Build Order (How to Construct the Template)

1. **Carve the reference app into `template/`** — take the fully-built reference project and move it under `template/`, renaming the package dir to `{{ module_name }}` and adding `.jinja` to every text file that needs variable substitution.
2. **Parameterize identity** — replace hardcoded name/slug/module/owner with variables; wire derived defaults via `includes/`.
3. **Add conditionals outermost-first** — wrap top-level optional dirs (`infra/`, `.agents/`, `.claude/`, `observability/`) in `{% if %}` directory names, then the `ai` context, then RLS pieces.
4. **Template the cross-cutting files** — `pyproject.toml`, `Taskfile.yml`, `docker-compose.yml`, `core/di/container.py`, Helm `values-*.yaml` — these reference many toggles and are the trickiest; test each render.
5. **Write `copier.yml`** — questions, validators, computed values, settings, `_tasks`, `_message_*`.
6. **Add answers file** — `template/{{ _copier_conf.answers_file }}.jinja` with the standard `{{ _copier_answers|to_nice_yaml -}}` body.
7. **Write template tests** — generation matrix + born-green + update smoke.
8. **Tag `v1.0.0`** and publish; add the `copier-template` GitHub topic.

---

## 10. Consumer Usage (documented in template README)

```bash
# Install Copier with required extensions (same virtualenv)
uv tool install --with copier-templates-extensions --with jinja2-time copier

# Generate a new project (--trust because the template uses tasks + extensions)
copier copy --trust gh:<org>/copier-todo-ddd path/to/my-service

# Later, pull template improvements
cd path/to/my-service
copier update --trust
```

---

## 11. Open Decisions for the Template

- **Reference app as submodule vs. vendored** — keep `template/` as a hand-maintained copy, or generate it from the live reference repo via a sync script? Vendored is simpler (KISS) but risks drift; decide before v1.
- **How many toggles is too many** — current set is ~18 questions. If real usage shows some are never changed from default, fold them into the template body and delete the question (YAGNI applied to the template itself).
- **Secret seeding** — confirm whether the template should write a starter `.env` at all, or only `.env.example` and let the user copy it. Writing `.env` via `_skip_if_exists` is convenient but slightly magic; `.env.example`-only is the more conventional, less surprising choice.
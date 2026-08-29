# Repository Guidelines

## Project Overview

Plausible Analytics is a privacy-focused web analytics application built with Elixir/Phoenix. This repository (`plausible-sqlite`) is a **fork that replaces the upstream PostgreSQL OLTP database with SQLite** (via `exqlite` + `ecto_sqlite3`), while keeping ClickHouse for OLAP analytics event storage. The app ingests pageview events from a lightweight JS tracker, stores them in ClickHouse, and serves a dashboard UI (React SPA + Phoenix LiveView) with aggregated stats.

**License**: AGPLv3 for the application, MIT for the tracker (`tracker/`).

## Architecture & Data Flow

### Dual-Database Design

The app uses two databases with fundamentally different roles:

1. **SQLite** (`Plausible.Repo`, `Ecto.Adapters.SQLite3`) — OLTP. Stores app data: users, teams, sites, goals, subscriptions, API keys, settings, segments, annotations, Oban jobs, feature flags. Single-file DB at `plausible_<env>.sqlite3` (dev) or `DATA_DIR/plausible.db` (prod). All upstream PostgreSQL migrations were consolidated into one migration: `priv/repo/migrations/20190101000001_initial_sqlite_schema.exs`.

2. **ClickHouse** (`ecto_ch` adapter) — OLAP column-store. Stores event analytics: pageviews, sessions, all stats queries. Four repos:
   - `Plausible.ClickhouseRepo` — read-only query path (`read_only: true`)
   - `Plausible.IngestRepo` — write path (buffered RowBinary inserts); owns `priv/ingest_repo/migrations`
   - `Plausible.AsyncInsertRepo` — async inserts (`async_insert: 1`)
   - `Plausible.DeletionRepo` — import-related deletions

### Ingestion Flow

```
Browser JS tracker → POST /api/event (PlausibleWeb.Api.ExternalController)
  → Plausible.Ingestion.Request.parse
  → Ingestion.Event.build_and_buffer (GateKeeper: rate-limit, spam/bot drops)
  → Persistor (Embedded | EmbeddedWithRelay | Remote, via PERSISTOR_BACKEND)
  → Session.CacheStore + Event/Session WriteBuffer GenServers
  → RowBinary INSERT into ClickHouse via IngestRepo
```

### Stats Query Flow

```
Dashboard/API → Plausible.Stats.query
  → QueryRunner (optimize → main query → comparison query → merge)
  → SQL.QueryBuilder.build(site, query)  [Ecto query + ClickHouse fragments]
  → ClickhouseRepo.all(query: query)  [parallel_tasks for multi-site breakdowns]
```

### EE/CE Build Split

Compile-time feature gating via `Plausible.on_ee`/`on_ce` macros (`lib/plausible.ex`):

- **EE (Enterprise)** envs: `dev`, `test`, `e2e_test`, `prod`, `load` — compiles `lib/` + `extra/lib/` (EE overlay: funnels, SSO, HelpScout, revenue, license enforcement in prod)
- **CE (Community Edition)** envs: `ce`, `ce_dev`, `ce_test` — compiles `lib/` only; `BUILD_EXTRA=false` drops EE JS; site_encrypt auto-TLS; `MIX_ENV=ce` is the Docker default

### Supervision Tree

`Plausible.Application` supervises all five repos, UA-parse task supervisor, `Session.BalancerSupervisor`, PromEx, TOTP vaults, ETS caches with warmers, `Session.Transfer`, `Ingestion.Counters`, Event/Session WriteBuffers, RateLimit, Finch, PubSub, Endpoint (site_encrypt-wrapped in CE), and Oban.

## Key Directories

| Directory | Purpose |
|---|---|
| `lib/plausible/` | Core domain: schemas, context modules, stats engine, ingestion, billing, auth |
| `lib/plausible/stats/` | ClickHouse stats query engine (~49 files, `QueryBuilder`, `SQL.Expression`, `SQL.Fragments`) |
| `lib/plausible/ingestion/` | Event ingestion pipeline: `Event`, `Persistor`, `WriteBuffer`, `GateKeeper` |
| `lib/plausible_web/` | Web layer: router, controllers, LiveViews, plugs, components, templates |
| `lib/plausible_web/live/` | ~30 LiveViews (dashboard, settings, shields, goals, team management) |
| `lib/plausible_web/plugs/` | Auth, site/team authorization, public-API auth plugs |
| `lib/workers/` | 21 Oban workers (email reports, cron dispatchers, traffic notifiers) |
| `extra/lib/` | EE-only overlay (funnels, SSO, audit, customer support, license) — not compiled in CE |
| `lib/mix/tasks/` | Mix tasks: `clean_postgres` (truncates SQLite), `clean_clickhouse`, `send_pageview`, billing plan generators |
| `lib/ip/` | IP address utilities (private/reserved ranges) |
| `priv/repo/migrations/` | SQLite migrations (7 files: consolidated schema + Oban + feature flags) |
| `priv/ingest_repo/migrations/` | ClickHouse migrations (~60+ files: events_v2, sessions_v2, imported_*) |
| `priv/tracker/` | Compiled JS tracker output served by `TrackerPlug` |
| `assets/` | Frontend: React 18 SPA + Alpine.js + Tailwind v4 (esbuild) |
| `tracker/` | JS tracker source (rollup + SWC, ~1000 compile variants) |
| `e2e/` | Playwright E2E tests (app-level, chromium) |
| `test/` | ExUnit tests + support modules |
| `config/` | Layered config: `config.exs` → per-env `.exs` → `runtime.exs` + `.env.*` |
| `rel/` | Release config: `vm.args`, overlays (migrate/createdb/seed scripts), docker-entrypoint |

## Development Commands

### Prerequisites

```bash
# Required runtime (from .tool-versions)
erlang 28.5.0.3
elixir 1.20.2-otp-28
nodejs 24.17.0

# Required external service: ClickHouse only (Postgres is vestigial in this fork)
make clickhouse     # docker, host network, port 8123/9000

# Optional: MinIO for S3-dependent flows (exports/imports)
make minio          # ports 10000/10001
```

### Setup & Run

```bash
make install          # deps.get + ecto.migrate + download_country_database + npm install (assets/tracker)
mix setup             # deps.get + ecto.setup (create/migrate/seeds) + assets.setup + assets.build
mix phx.server        # start dev server on localhost:8000

# Dev login (seeds): user@plausible.test / plausible, site: dummy.site
mix send_pageview     # send a test pageview event
```

### Build Assets

```bash
mix assets.setup      # install tailwind + esbuild
mix assets.build      # build JS + CSS (dev, no minify)
mix assets.deploy     # build + minify + phx.digest (prod)
npm run deploy --prefix tracker   # compile JS tracker → priv/tracker/js/
```

### Linting & Static Analysis

```bash
mix format                    # format Elixir (Phoenix.LiveView.HTMLFormatter plugin)
mix format --check-formatted  # CI check
mix credo                     # linter (max line 120, nesting 3)
mix dialyzer                  # type analysis (plt at priv/plts/dialyzer.plt)

# Frontend
npm run lint --prefix assets       # eslint + stylelint
npm run typecheck --prefix assets  # tsc --noEmit
npm run check-format --prefix assets   # prettier check
npm run check-format --prefix tracker  # tracker prettier check
npm run lint --prefix tracker
```

### Release

```bash
MIX_ENV=ce mix release plausible    # build release (Docker default)
# Docker: multi-stage, MIX_ENV=ce, alpine runtime, port 8000
# Entry: /entrypoint.sh run | db (migrate/createdb/seed)
```

### Other Makefile Targets

`clickhouse-client`, `clickhouse-prod` (25.11.5.8), `postgres`/`postgres-client` (vestigial, for PG data-migration path only), `minio-stop`, `sso`/`sso-stop` (SAML IdP on :8080), `mock-dns` (coredns :5354), `loadtest-server`/`loadtest-client` (k6).

## Code Conventions & Common Patterns

### Repo Usage

- **SQLite (OLTP)**: `Plausible.Repo` — standard Ecto CRUD. `use Plausible.Repo` macro provides alias + Ecto imports. Oban runs on this repo (`Oban.Engines.Lite`).
- **ClickHouse (OLAP)**: Never use `Plausible.Repo` for analytics. Reads via `ClickhouseRepo.all/1`, writes via `IngestRepo` (buffered RowBinary through `WriteBuffer` GenServers, not direct inserts).
- **Raw ClickHouse SQL**: Use `fragment()` with ClickHouse-specific functions (`countIf`, `uniq`, `toDate`, `toTimeZone`, `arrayJoin`, `argMax`, etc.). See `lib/plausible/stats/clickhouse.ex` for fragment helper patterns.

### Context Module Pattern

Domain logic lives in context modules (`Plausible.Sites`, `Plausible.Teams`, `Plausible.Billing`, etc.) that wrap `Repo` + `Ecto.Query`. Schemas (`Plausible.Site`, `Plausible.User`, `Plausible.Team`) are data-only. Follow this pattern for new domains.

### EE/CE Compile-Time Gating

```elixir
# lib/plausible.ex provides:
on_ee do
  # EE-only code (compiled when Mix.env() not in [:ce, :ce_test, :ce_dev])
end

on_ce do
  # CE-only code
end

ee?()  # boolean: is this an EE build?
ce?()  # boolean: is this a CE build?
```

EE code goes in `extra/lib/` (compiled via `elixirc_paths` for non-CE envs). Never add EE features without `on_ee` guards. CE builds never compile `extra/`.

### Dependency Injection

External services are config-keyed modules, swappable in tests via Mox:

- `:paddle_api` → `Plausible.Billing.PaddleApi` (prod) / `TestPaddleApiMock` (test) / `DevPaddleApiMock` (dev/e2e)
- `:google_api` → `Plausible.Google.API` / `Plausible.Google.API.Mock`
- `:http_impl` → `Plausible.HTTPClient` / `Plausible.HTTPClient.Mock` (Mox)
- `:dns_lookup_impl` → `Plausible.DnsLookup` / `Plausible.DnsLookup.Mock` (Mox)
- `:verification_checks_mod` → real / `ChecksMock` (e2e)

### Config Layering

```
config/config.exs          → base static config
config/<env>.exs           → per-env overrides (dev/test/e2e_test/ce/ce_dev/ce_test/load/prod)
config/runtime.exs         → runtime (1036 lines): env vars, DB paths, ClickHouse, Oban crons
config/.env.<env>          → env var files loaded via Envy.load (dev/test/e2e_test/load)
```

All config vars read through `Plausible.ConfigHelpers.get_var_from_path_or_env(CONFIG_DIR, "VAR", default)` — `CONFIG_DIR` defaults to `/run/secrets` (file-over-env pattern: secrets files take precedence over env vars).

### SQLite-Specific Conventions

- PG array types replaced by JSON-text custom Ecto types: `Plausible.Ecto.Types.FeatureArray`, `Plausible.Ecto.Types.StringArray` (in `lib/plausible/ecto/types/`)
- PG domain-uniqueness trigger was dropped (orphaned `priv/repo/structure.sql` is a leftover PG reference dump)
- `mix clean_postgres` task actually truncates SQLite tables (queries `sqlite_master`)
- No explicit PRAGMA/journal_mode config (exqlite defaults)

### Web Layer

Hybrid: controllers for APIs/auth/legacy pages + LiveView for dashboard and settings. Router (`lib/plausible_web/router.ex`, 742 lines) has pipelines for browser, shared_link, api, public_api, internal_stats_api. Key scopes: `/api/v1/stats`, `/api/v2` (public API), `/api/event` (ingestion), `/settings`, `/:domain` (dashboard LiveViews).

### Oban Workers

`use Oban.Worker, queue: :<queue_name>`. Cron schedules defined in `config/runtime.exs` (`base_cron` for self-hosted, `+cloud_cron` for EE). `Oban testing: :manual` in test/e2e envs.

## Important Files

| File | Role |
|---|---|
| `mix.exs` | Project def: deps, aliases, elixirc_paths per env, releases, dialyzer |
| `lib/plausible.ex` | `on_ee`/`on_ce`/`ee?`/`ce?` compile-time gating macros |
| `lib/plausible/application.ex` | Supervision tree (all 5 repos, caches, buffers, Oban) |
| `lib/plausible/repo.ex` | **Fork core change**: `adapter: Ecto.Adapters.SQLite3` |
| `lib/plausible/clickhouse_repo.ex` | Read-only ClickHouse repo (query path) |
| `lib/plausible/ingest_repo.ex` | Write ClickHouse repo (owns CH migrations) |
| `lib/plausible/stats.ex` | Stats entry point: `query/2` → QueryRunner |
| `lib/plausible/stats/query_runner.ex` | Query orchestration: optimize → execute → merge |
| `lib/plausible/stats/sql/expression.ex` | ClickHouse SQL expression builder (metrics/dimensions) |
| `lib/plausible/ingestion/event.ex` | `build_and_buffer/2` ingestion pipeline |
| `lib/plausible/ingestion/write_buffer.ex` | GenServer RowBinary write buffer → IngestRepo |
| `lib/plausible_web/router.ex` | All routes (742 lines) |
| `lib/plausible_web/endpoint.ex` | Endpoint: TrackerPlug, LiveView socket, CE site_encrypt |
| `lib/plausible_release.ex` | `interweave_migrate/0` — interleaves SQLite + CH migrations by version |
| `config/runtime.exs` | Runtime config (1036 lines): DB paths, ClickHouse, Oban, env loading |
| `priv/repo/migrations/20190101000001_initial_sqlite_schema.exs` | Consolidated SQLite schema (826 lines, replaces all PG migrations) |
| `priv/repo/seeds.exs` | Dev seeds: <user@plausible.test>, dummy.site, ~720 days fake stats |
| `Dockerfile` | Multi-stage build: `MIX_ENV=ce`, elixir 1.20.2/erlang 28.5.0.3, alpine runtime |
| `.iex.exs` | IEx helpers: aliases for Repo, ClickhouseRepo, IngestRepo, Site, Sites, Stats; imports Factory |

## Runtime/Tooling Preferences

- **Runtime**: Erlang 28.5.0.3, Elixir 1.20.2-otp-28, Node 24.17.0 (enforced via `.tool-versions` / asdf)
- **Build tool**: Mix (Elixir), npm (assets/tracker/e2e)
- **Package manager**: `mix deps.get` (Elixir), `npm install` (JS — three separate `package.json` in `assets/`, `tracker/`, `e2e/`)
- **Asset bundler**: esbuild 0.17.11 (JS) + Tailwind 4.1.12 (CSS)
- **No Bun**: Node/npm only for all JS workspaces
- **External service**: ClickHouse is the only required external service for dev/test. PostgreSQL is vestigial (only for one-off PG→SQLite data migration via `Plausible.DataMigration.PostgresRepo`). MinIO optional (S3 exports/imports).
- **DB files**: SQLite files are relative to repo root (`./plausible_dev.sqlite3`, etc.), gitignored. Override with `DATABASE_PATH` env var.

## Testing & QA

### ExUnit (Elixir)

```bash
mix test                          # unit tests (requires running ClickHouse!)
mix test --include slow           # include slow-tagged tests
mix test --include minio          # include MinIO-dependent tests (run `make minio` first)
mix test --include migrations     # include migration tests
mix test --partitions 6           # partitioned run (CI uses 6 partitions)
mix test --cover                  # coverage via ExCoveralls (text + cover/ HTML)
MIX_ENV=ce_test mix test          # CE build test (excludes :ee_only)
```

**Test DBs**: SQLite `./plausible_test.sqlite3` (Ecto SQL Sandbox, `:manual` mode) + ClickHouse `plausible_test` (not sandboxed; tests write through WriteBuffers, poll with `await_clickhouse_count`, truncated after via `clean_clickhouse`).

**Default excludes**: `[:slow, :minio, :migrations]`. CE test excludes `:ee_only`. E2E test excludes `:test`, includes `:e2e`.

### Test Support (`test/support/`)

| Module | Purpose |
|---|---|
| `Plausible.DataCase` | CaseTemplate: SQLite sandbox checkout, imports Factory/TestUtils/Teams.Test |
| `PlausibleWeb.ConnCase` | Phoenix.ConnTest with `build_conn` + sandbox |
| `Plausible.Factory` | ExMachina factories: user/team/site/goal/subscription + ClickHouse structs (event, pageview, session) |
| `Plausible.TestUtils` | `setup` blocks (create_user/site/team, log_in, api_key), `populate_stats` (writes to CH), `eventually`/`await_clickhouse_count` polling |
| `Plausible.Teams.Test` | `new_user`, `new_site` (auto-creates team), subscription helpers |
| `Plausible.AssertMatches` | `assert_matches` macro with pattern expressions (`^any`, `^~r`, `^exactly`) |
| `Plausible.Test.Support.HTTPMocker` | Mox stubs from `fixture/http_mocks/<name>.json` (replaces exvcr) |

Mox mocks declared in `test/test_helper.exs`: `HTTPClient.Mock`, `DnsLookup.Mock`. Additional mocks via config: `TestPaddleApiMock`, `DevPaddleApiMock`, `Google.API.Mock`, `ChecksMock`.

### E2E (Playwright)

```bash
mix e2e.setup          # install Playwright chromium
mix test.e2e           # app-level E2E (MIX_ENV=e2e_test, port 8111, chromium-only)
mix test.e2e --ui      # interactive UI mode
mix test.e2e -- --debug e2e/tests/dashboard/segments.spec.ts  # specific test

# Tracker tests (separate, 3 browsers)
npm test --prefix tracker
```

### Frontend (Jest)

```bash
npm test --prefix assets           # Jest 29 + ts-jest + jsdom, TZ=UTC
npm run test --prefix assets -- --coverage   # v8 coverage
```

### Load Testing (k6)

```bash
make loadtest-server   # MIX_ENV=load iex -S mix phx.server
make loadtest-client   # k6 run test/load/script.js (6000 rps, 30k VUs)
```

### CI (`.github/workflows/`)

- **`elixir.yml`**: matrix `test` × `ce_test` × 6 partitions, services postgres:18 + clickhouse:25.11.5.8-alpine; `mix test --include slow --include minio --include migrations --partitions 6 --warnings-as-errors`; e2e 2-shard Playwright; static job: format/credo/dialyzer
- **`node.yml`**: assets generate-types diff, typecheck, lint, check-format, jest; tracker lint/check-format/deploy
- **`tracker.yml`**: tracker Playwright 4-shard in container
- **`migrations-validation.yml`**: blocks PRs that change migrations + app code simultaneously

### Coverage

ExCoveralls configured (`mix.exs` `test_coverage: [tool: ExCoveralls]`) but no `coveralls.json` → no thresholds. CI does not enforce coverage.

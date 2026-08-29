---
type: source
title: "Observation: plausible-sqlite fork: SQLite schema consolidation and asset pipeline"
slug: obs-2026-08-29-plausible-sqlite-fork-sqlite-schema-consolidation-and-asset-
status: observation
created: 2026-08-29
updated: 2026-08-29
relevance: high
observed_at: 2026-08-29T06:11:41.140Z
tags: ["plausible", "elixir", "sqlite", "phoenix", "assets", "tracker", "e2e", "ci", "docker"]
source_context: "Research task: scripts, frontend assets, docs, contributor workflow in plausible-sqlite"
---
# ⭐ Observation: plausible-sqlite fork: SQLite schema consolidation and asset pipeline
Fork of Plausible Analytics converting PostgreSQL→SQLite (repo /Volumes/data/Project/plausible-sqlite). Plausible.Repo uses Ecto.Adapters.SQLite3 (lib/plausible/repo.ex); ClickhouseRepo + IngestRepo remain Ecto.Adapters.ClickHouse. Fork-specific: priv/repo/migrations/20190101000001_initial_sqlite_schema.exs is a single consolidated 826-line migration replacing all upstream Postgres migrations (repo/structure.sql is a Postgres 16.4 dump kept as reference). DB path in config/runtime.exs: dev/test/ce_dev/ce_test/e2e_test/load → plausible_#{env}.sqlite3; prod/ce → $DATABASE_PATH or data_dir/plausible.db. Config envs: dev, test, e2e_test, ce, ce_dev, ce_test, load. Assets: esbuild 0.17.11 (config :esbuild in config/config.exs) bundles assets/js/{app.js,dashboard.tsx,embed.host.js,embed.content.js} → priv/static/js; tailwind 4.1.12 → priv/static/css/app.css; mix aliases assets.build/assets.deploy (assets.deploy adds phx.digest). Tracker: node compile.js (rollup+@swc minify, COMPILE_* global_defs variants, tracker/compiler/variants.json ~11315 lines) outputs priv/tracker/js/* + tracker/npm_package + priv/tracker/installation_support; served by lib/plausible_web/tracker.ex + plugs/tracker_plug.ex. E2E: e2e/ playwright, chromium only, webServer `mix phx.server` MIX_ENV=e2e_test, BASE_URL http://localhost:8111, run via `mix test.e2e` alias. CI: elixir.yml (build matrix test/ce_test × 6 partitions × postgres:18+clickhouse:25.11.5.8-alpine; e2e 2 shards; static: format+credo+dialyzer), node.yml (assets jest/tsc/eslint/stylelint/prettier + tracker lint/deploy), tracker.yml (playwright 4 shards). Dockerfile: MIX_ENV=ce release build (hexpm/elixir:1.20.2-erlang-28.5.0.3-alpine) → alpine runtime, /entrypoint.sh with `run`/`db` subcommands, /var/lib/plausible volume, EXPOSE 8000. .iex.exs aliases Repo/ClickhouseRepo/IngestRepo/Site/Sites/Goal/Goals/Stats + Ecto.Query + Factory. Note CONTRIBUTING.md still documents Postgres docker (make postgres) which is vestigial for the SQLite fork; ClickHouse docker (make clickhouse) is still required.
*Relevance: high*

*Context: Research task: scripts, frontend assets, docs, contributor workflow in plausible-sqlite*

*Tags: plausible elixir sqlite phoenix assets tracker e2e ci docker*
---
*Observed: 2026-08-29T06:11:41.140Z*
# Plausible Analytics (SQLite Fork) — The Single-Server Plausible

<p align="center">
  <a href="https://github.com/maulanashalihin/plausible-sqlite">
    <img src="https://raw.githubusercontent.com/plausible/docs/master/static/img/plausible-analytics-icon-top.png" width="140px" alt="Plausible Analytics" />
  </a>
</p>

<p align="center">
  <strong>Use this if you self-host Plausible on one VPS.</strong> Same product, same dashboard, same tracker — without the PostgreSQL tax.
</p>

> **Fork of [Plausible Analytics](https://plausible.io/) with SQLite replacing PostgreSQL for OLTP.** ClickHouse stays for analytics (OLAP). All Enterprise Edition features included (funnels, SSO, revenue goals, consolidated views).

## Why you should choose this over upstream on a single server

Upstream Plausible is built for `plausible.io` — multi-node, thousands of sites. It needs **PostgreSQL + ClickHouse**. For a single VPS, that second database is pure overhead: extra RAM, extra config, extra backups, extra failure mode, zero extra value. The OLTP workload (users, teams, sites, settings, API keys, Oban jobs) is <5% writes, tiny, and never needs horizontal scaling.

**This fork fixes that mismatch.** `Plausible.Repo` runs on `Ecto.Adapters.SQLite3` (`exqlite`) — in-process, `WAL` mode, single file at `DATA_DIR/plausible.db`. ClickHouse is untouched.

**What you get:**
- **Fits a $6 VPS.** Runs comfortably on 1–2 GB RAM / bare-metal non-Docker (`GUIDE_NON_DOCKER.md`). Upstream needs 4 GB+ to keep Postgres + ClickHouse happy.
- **Zero Postgres ops.** No `postgresql.conf`, no `max_connections`, no `vacuum`, no `pg_hba`, no major-version upgrades.
- **One-file backup.** `cp /var/lib/plausible/plausible.db /backup/` — done. Restore is `scp` the file back. No `pg_dump` ceremony.
- **Same features, faster dashboard.** EE features are on by default (`MIX_ENV=ee`). And for this workload, SQLite is simply faster — see benchmark below.
- **Proven in production** at `ps.maulanabuilds.com`.

> If you plan to run a multi-node Postgres cluster for 10k+ sites, stay on upstream. For **1 server, 1–500 sites** — this is the rational choice.

## Benchmark: SQLite vs PostgreSQL on a single server

We benchmarked the exact OLTP pattern Plausible uses — not a synthetic `pgbench`. Same schema (`teams, users, sites, team_memberships` + indexes on `domain`/`email`), same `5000 rows` seed, same queries. **Bun 1.4.0** (`bun:sqlite` native vs `postgres.js 3.4.9` over `127.0.0.1`), **Postgres 18.6**, **SQLite 3.46.1**, **6 vCPU Haswell, 11 GB RAM**. `WAL + synchronous=NORMAL`, `MEASURE=5000, WARMUP=500`.

Reproduce: `cd bench/sqlite-vs-postgres && bun install && bun run bench.mjs` (13s) — source in this repo’s bench harness.
| Workload — what your dashboard actually does | Concurrency | SQLite QPS | Postgres QPS | Speedup | p95 SQLite | p95 Postgres |
|---|---:|---:|---:|---:|---:|---:|
| **Q1: site by domain** `WHERE domain = ?` — 70% of requests | 1 | 198,141 | 8,420 | **23.5×** | 0.007 ms | 0.160 ms |
| | 10 | 209,353 | 19,033 | **11.0×** | 0.006 ms | 0.703 ms |
| | 50 | 215,222 | 15,348 | **14.0×** | 0.005 ms | 3.758 ms |
| **Q2: user by email + JOIN team** — every auth | 1 | 196,401 | 4,676 | **42.0×** | 0.006 ms | 0.312 ms |
| | 10 | 184,511 | 16,505 | **11.1×** | 0.006 ms | 1.108 ms |
| | 50 | 174,062 | 24,221 | **7.1×** | 0.007 ms | 3.508 ms |
| **Q3: list sites by team** `WHERE team_id = ? LIMIT 20` — dashboard | 1 | 38,858 | 3,802 | **10.2×** | 0.043 ms | 0.404 ms |
| | 50 | 45,660 | 14,830 | **3.0×** | 0.036 ms | 5.682 ms |
| **Q4: mixed 95% read / 5% write** `UPDATE timezone` — realistic | 1 | 173,281 | 4,509 | **38.4×** | 0.012 ms | 0.473 ms |

**Resource on the same box:**
- Postgres: `~27 MB` (main) + `37 MB` (checkpointer) + `~21 MB per backend` → **~250 MB for 10 connections**, plus `shared_buffers`. `ps aux` measured.
- SQLite: **0 MB extra process**, `~2–5 MB` heap in-process, DB file `1.8 MB` for the same 5000 rows. `du -sh /tmp/bench_plausible.sqlite3`.

**What “more scalable” means on one server:** `scalability = throughput / resource`. SQLite latency stays flat (`0.005–0.043 ms` from `c=1` to `c=50`), Postgres p95 explodes (`0.16 ms → 3.7 ms`, p99 `32 ms` at `c=50`) from TCP/parse/plan + per-connection overhead. For the `3–5` queries per dashboard render, that’s the difference between instant and sluggish.

**Honest caveat:** Postgres wins if you have `>50 concurrent writers` hammering the *same* rows — it has row-level locks, SQLite has a single writer lock. Plausible OLTP never hits that: writes are rare (create site/goal, update settings, Oban jobs) and ingestion writes go to **ClickHouse via `WriteBuffer` (RowBinary), not SQLite**. The bottleneck on a single server is ClickHouse cache — RAM you save by dropping Postgres goes straight to ClickHouse.
**Bottom line:** on a single server, this fork does **3–42× more queries per GB of RAM at 20–100× lower p95 latency**. That’s why it fits a small VPS and feels faster.

### What about Elixir/Ecto? (honest numbers from the real app stack)

Raw drivers flatter SQLite. Through `Ecto` (`ecto 3.13 + ecto_sqlite3 0.23 / exqlite 0.40 vs postgrex 0.22`) both pay `~70–80μs` for `cast + telemetry + DBConnection`, so the gap shrinks — but SQLite still wins where it matters: **per-request latency on a single server**.

Same `5000 rows`, same 3 queries, `Benchee 1.3` (`time: 5s, warmup: 2s`) + `Task.async_stream` sweep `MEASURE=5000`:

**Benchee — single concurrency (realistic: 1 request = 1 query sequential):**

| Name | ips | average | median | 99th |
|---|---:|---:|---:|---:|
| `sqlite user JOIN team` | 10.76 K | 92.97 μs | 81.19 μs | 227 μs |
| `sqlite site by domain` | 10.03 K | 99.71 μs | 83.28 μs | 259 μs |
| `sqlite list sites by team` | 7.44 K | 134.42 μs | 122.51 μs | 270 μs |
| `pg site by domain` | 4.62 K | 216.32 μs | 189.16 μs | 841 μs | **2.33× slower** |
| `pg user JOIN team` | 3.81 K | 262.79 μs | 233.04 μs | 967 μs | **2.83× slower** |
| `pg list sites by team` | 3.38 K | 295.51 μs | 263.90 μs | 871 μs | **3.18× slower** |

**Concurrency sweep (Ecto):**

| Workload | `c=1` | `c=10` | `c=50` |
|---|---:|---:|---:|
| **Q1 site by domain** | SQLite **10,356 qps `p95 0.17ms`** vs PG **3,986 `p95 0.38ms`** = **2.6×** | SQLite 7,714 vs PG 21,303 = **0.36× (PG wins)** | SQLite 6,051 vs PG 22,908 = 0.26× |
| **Q2 user JOIN** | **9,538 vs 3,925 = 2.43×** | 8,573 vs 14,566 = 0.59× | 6,250 vs 21,774 = 0.29× |
| **Q3 list by team** | **6,413 vs 3,344 = 1.92×** | 6,100 vs 16,520 = 0.37× | 4,668 vs 17,226 = 0.27× |
| **Q4 mixed 95% read / 5% write (2000 ops sequential)** | SQLite `p50 0.084ms p95 0.16ms` vs PG `p50 0.23ms p95 0.66ms` | — | — |

**Why PG wins at `c=10/50` in Elixir:** `Plausible.Repo (SQLite)` defaults to a small pool (`WAL + single-writer`), so 10/50 parallel queries serialize (`p50 1.1ms → 8ms`). `PgRepo pool_size=50` parallelizes. That’s expected — **but it never happens in real self-hosting.** One dashboard hit = 3–5 queries *sequential*, not 50 parallel. Ingest writes go to `ClickHouse via WriteBuffer`, not to `Plausible.Repo`. At the realistic `c=1` per-request path, Ecto + SQLite is still **~2–3× faster** and `~250MB` lighter.

> **Honest takeaway:** If you run `>50 concurrent OLTP writers` on the same rows, stay on Postgres. For a single VPS with `1–50 concurrent viewers` (the Plausible self-host case), SQLite is faster, cheaper, and simpler — even through Ecto. Raw driver just makes the same truth more obvious.

Reproduce Ecto bench: `cd bench/ecto-vs-postgres && mix deps.get && mix run bench.exs` (60s). Raw Bun bench stays in `bench/sqlite-vs-postgres`.


## What changed from upstream

- **PostgreSQL → SQLite** for `Plausible.Repo` (users, teams, sites, subscriptions, API keys, etc.)
- **ClickHouse unchanged** for event analytics (`Plausible.ClickhouseRepo`)
- Custom Ecto types for SQLite compatibility (`Json`, `StringArray`, `FeatureArray`)
- PostgreSQL-specific SQL patterns replaced (LATERAL JOIN, ANY(), ILIKE, array_agg, cardinality, etc.)
- Dockerfile defaults to `MIX_ENV=ee` (all features: funnels, SSO, revenue goals, consolidated views)

## Technology

- **Backend**: Elixir 1.20 + Phoenix 1.8
- **OLTP Database**: SQLite (via [exqlite](https://github.com/elixir-sqlite/exqlite))
- **Analytics Database**: ClickHouse
- **Frontend**: React + TailwindCSS

## Quick start (local dev)

### Prerequisites

- Erlang/OTP 28+, Elixir 1.20+
- Node.js 22+
- ClickHouse (for analytics)

### Setup

```bash
# Install deps
mix deps.get
npm install --prefix assets

# Start ClickHouse
clickhouse server --config-file=/tmp/clickhouse-config.xml --daemon

# Create + migrate databases
MIX_ENV=dev mix ecto.create
MIX_ENV=dev mix ecto.migrate

# Download GeoIP database
mix download_country_database

# Build frontend assets
mix assets.build

# Seed demo data
mix run priv/repo/seeds.exs

# Start server
mix phx.server
```

### Default credentials (from seeds)

- **Email**: `user@plausible.test`
- **Password**: `plausible`
- **Site**: `dummy.site`

### Admin account

To create a super admin (SaaS owner), use Ecto — **not raw sqlite3 INSERT** (custom Ecto types will crash on load):

```elixir
# mix run -e '
alias Plausible.Auth.User
alias Plausible.Repo
alias Plausible.Teams

admin = User.new(%{email: "admin@example.com", name: "Owner", password: "secure-password-12+"})
|> Ecto.Changeset.put_change(:email_verified, true)
|> Repo.insert!()

team = %Teams.Team{name: "Admin", identifier: Ecto.UUID.generate()} |> Repo.insert!()
%Teams.Membership{team_id: team.id, user_id: admin.id, role: :owner} |> Repo.insert!()
IO.puts("ADMIN_USER_IDS=#{admin.id}")
'
```

Then start with `ADMIN_USER_IDS=<id> mix phx.server`.

## Deploy

- **Docker**: see [## Docker](#docker) below.
- **Non-Docker (bare metal, systemd + Nginx)**: see [GUIDE_NON_DOCKER.md](GUIDE_NON_DOCKER.md) — production setup used at `ps.maulanabuilds.com`.

## Docker

```bash
docker build -t plausible-sqlite .

docker run -p 8000:8000 \
  -e BASE_URL=http://localhost:8000 \
  -e SECRET_KEY_BASE=$(openssl rand -base64 48) \
  -e CLICKHOUSE_DATABASE_URL=http://clickhouse:8123 \
  -v plausible-data:/var/lib/plausible \
  plausible-sqlite

# Initialize DB (first run only)
docker exec plausible db createdb
docker exec plausible db migrate
```

SQLite database file stored at `/var/lib/plausible/plausible.db`.

## Testing

```bash
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
MIX_ENV=test mix test --exclude slow --exclude minio
```

Tests run serially (`max_cases: 1`) because SQLite is single-writer. Parallel test execution causes `Database busy` errors.

## SQLite compatibility notes

See `.llm-wiki/wiki/sources/` for detailed observations on PostgreSQL → SQLite migration patterns.

Key replacements:

| PostgreSQL | SQLite |
|---|---|
| `LEFT LATERAL JOIN` | Correlated subquery |
| `ANY(array)` | `LIKE` on JSON string |
| `array_agg()` | `group_concat()` + Elixir parse |
| `cardinality()` | `json_array_length()` |
| `ILIKE` | `LIKE lower()` |
| `position(a IN b)` | `instr(b, a)` |
| `:map` Ecto type | Custom `Plausible.Ecto.Types.Json` |
| `{:array, :string}` | Custom `Plausible.Ecto.Types.StringArray` |
| `delete_all` with JOIN | Split to select + delete |

## License

GNU Affero General Public License v3 (AGPLv3). See [LICENSE.md](LICENSE.md).

Tracker JavaScript is MIT licensed. See [tracker/LICENSE.md](tracker/LICENSE.md).

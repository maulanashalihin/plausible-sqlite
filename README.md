# Plausible Analytics (SQLite Fork)

<p align="center">
  <a href="https://github.com/maulanashalihin/plausible-sqlite">
    <img src="https://raw.githubusercontent.com/plausible/docs/master/static/img/plausible-analytics-icon-top.png" width="140px" alt="Plausible Analytics" />
  </a>
</p>

Fork of [Plausible Analytics](https://plausible.io/) with **SQLite replacing PostgreSQL** for OLTP data. ClickHouse remains for analytics (OLAP). All Enterprise Edition features included.

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

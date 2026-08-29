# GUIDE: Deploy Plausible SQLite (Non-Docker) — VPS Bare Metal

Deploy `plausible-sqlite` without Docker using `systemd` + `mix phx.server` + Nginx/Cloudflare. This is the setup running at `ps.maulanabuilds.com`.

## 1. Prerequisites

```bash
# OS: Ubuntu 22.04/24.04
erl -version        # Erlang/OTP 28+
elixir -v           # Elixir 1.18+
node -v             # Node 20+ (for assets)
clickhouse --version # ClickHouse 24+
sqlite3 --version
```

Install if missing:
```bash
# Elixir via asdf
asdf plugin add erlang && asdf plugin add elixir && asdf install
# Node via nvm
nvm install 20
# ClickHouse
curl https://clickhouse.com/|sh && ./clickhouse install
# exqlite requires libsqlite3-dev
sudo apt install libsqlite3-dev inotify-tools
```

## 2. Clone & Build

```bash
git clone https://github.com/maulanashalihin/plausible-sqlite.git /opt/plausible-sqlite
cd /opt/plausible-sqlite

mix deps.get
npm install --prefix assets
mix assets.build   # or npm run deploy --prefix assets
mix download_country_database  # GeoIP
```

## 3. ClickHouse (OLAP)

```bash
# config: /etc/clickhouse-server/config.xml & users.xml
# Create DB & tables:
clickhouse-client --query "CREATE DATABASE IF NOT EXISTS plausible_events_db"
MIX_ENV=dev mix clickhouse.migrate  # or mix ecto.migrate (runs CH migrations)

# URL used by the app:
# CLICKHOUSE_DATABASE_URL=http://default:plausible@127.0.0.1:8124/plausible_events_db
```

## 4. Env Vars (required)

Systemd uses `Environment=` directly (alternative: `/etc/plausible/env`):

```
MIX_ENV=dev
PORT=8001
LISTEN_IP=0.0.0.0
BASE_URL=https://ps.maulanabuilds.com
DATABASE_PATH=/opt/plausible-sqlite/plausible_dev.sqlite3
CLICKHOUSE_DATABASE_URL=http://default:plausible@127.0.0.1:8124/plausible_events_db
SECRET_KEY_BASE=$(openssl rand -base64 48)  # generate once, never rotate
TOTP_VAULT_KEY=$(openssl rand -base64 32)
DISABLE_CRON=true  # single-node: in-app cron is enough
```

Generate secrets:
```bash
openssl rand -base64 48
openssl rand -base64 32 | tr -d '\n'
```

## 5. SQLite DB Init

```bash
MIX_ENV=dev mix ecto.create
MIX_ENV=dev mix ecto.migrate

# Optional seed (user@plausible.test / plausible)
MIX_ENV=dev mix run priv/repo/seeds.exs
```

> **DO NOT** `sqlite3 ... INSERT` raw into `enterprise_plans/subscriptions` — `team_member_limit` must be `-1` (not `"unlimited"`), `features` must be lowercase JSON `["goals","props",...]`. Use `mix run` + `Repo.insert` (see `README.md` admin account & `.llm-wiki/...bypasses-ecto-dump.md`).

## 6. systemd Service (production)

`/etc/systemd/system/plausible-sqlite.service`:
```ini
[Unit]
Description=Plausible SQLite - ps.maulanabuilds.com
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/plausible-sqlite
Environment=MIX_ENV=dev
Environment=PORT=8001
Environment=LISTEN_IP=0.0.0.0
Environment=BASE_URL=https://ps.maulanabuilds.com
Environment=DATABASE_PATH=/opt/plausible-sqlite/plausible_dev.sqlite3
Environment=CLICKHOUSE_DATABASE_URL=http://default:plausible@127.0.0.1:8124/plausible_events_db
Environment=SECRET_KEY_BASE=xxx
Environment=TOTP_VAULT_KEY=yyy
Environment=DISABLE_CRON=true
ExecStart=/usr/bin/mix phx.server
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=plausible-sqlite

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now plausible-sqlite
sudo journalctl -u plausible-sqlite -f  # check logs
```

Upgrade:
```bash
cd /opt/plausible-sqlite && git pull
mix deps.get && mix assets.build
MIX_ENV=dev mix ecto.migrate
sudo systemctl restart plausible-sqlite
```

## 7. Nginx + Cloudflare (HTTPS)

App listens on `127.0.0.1:8001` or `0.0.0.0:8001`. Add Nginx reverse proxy:

```nginx
server {
  server_name ps.maulanabuilds.com;
  location / {
    proxy_pass http://127.0.0.1:8001;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

Cloudflare: `SSL Full`, `BASE_URL=https://...` must be `https`. Do not rotate `SECRET_KEY_BASE` after DB is populated (invalidates sessions).

## 8. Verification

```bash
curl -I https://ps.maulanabuilds.com/sites  # 302 -> login
MIX_ENV=dev mix run -e 'IO.inspect Repo.all(Team)'  # check team
sqlite3 plausible_dev.sqlite3 "SELECT trial_expiry_date FROM teams;"
```

Common errors:
- `eaddrinuse` -> `PORT` conflict, change `PORT` in service.
- `ArgumentError binary_to_integer("unlimited")` -> `enterprise_plans.team_member_limit` must be `-1`.
- `ArgumentError not a tuple` in `FeatureArray` -> `features` must be lowercase JSON.

## 9. Backup

```bash
# SQLite (hot backup, WAL)
sqlite3 plausible_dev.sqlite3 ".backup /backup/plausible-$(date +%F).sqlite3"
# ClickHouse
clickhouse-client --query "BACKUP TABLE plausible_events_db.events_v2 TO Disk('backups', 'events.zip')"
```

---

**Source**: service running on `vps-5624be8b` (`/opt/plausible-sqlite`, `systemctl cat plausible-sqlite`), `config/runtime.exs`.

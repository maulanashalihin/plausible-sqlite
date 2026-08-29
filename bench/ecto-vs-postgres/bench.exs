Logger.configure(level: :warning)
import Ecto.Query

# Wait for repos
Process.sleep(500)

# ── Setup: recreate SQLite schema ──
Bench.SqliteRepo.query!("PRAGMA journal_mode=WAL;")
Bench.SqliteRepo.query!("PRAGMA synchronous=NORMAL;")
Bench.SqliteRepo.query!("PRAGMA cache_size=-64000;")
Bench.SqliteRepo.query!("PRAGMA temp_store=MEMORY;")

# Create tables if not exist (idempotent) - drop first for clean state
for sql <- [
  "DROP TABLE IF EXISTS team_memberships",
  "DROP TABLE IF EXISTS sites",
  "DROP TABLE IF EXISTS users",
  "DROP TABLE IF EXISTS teams",
  """
  CREATE TABLE teams (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identifier TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    inserted_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  )
  """,
  """
  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    team_id INTEGER REFERENCES teams(id),
    inserted_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  )
  """,
  """
  CREATE TABLE sites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL UNIQUE,
    timezone TEXT DEFAULT 'Etc/UTC',
    team_id INTEGER REFERENCES teams(id),
    inserted_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  )
  """,
  """
  CREATE TABLE team_memberships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    team_id INTEGER NOT NULL REFERENCES teams(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    role TEXT NOT NULL DEFAULT 'viewer',
    UNIQUE(team_id, user_id)
  )
  """,
  "CREATE INDEX IF NOT EXISTS idx_sites_team_id ON sites(team_id)",
  "CREATE INDEX IF NOT EXISTS idx_users_team_id ON users(team_id)",
  "CREATE INDEX IF NOT EXISTS idx_sites_domain ON sites(domain)",
  "CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)"
] do
  Bench.SqliteRepo.query!(sql)
end

IO.puts("== Seeding SQLite 5000 rows ==")
Bench.SqliteRepo.query!("BEGIN")
for i <- 0..499 do
  Bench.SqliteRepo.query!("INSERT INTO teams (identifier, name) VALUES (?, ?)", ["team-#{String.pad_leading(to_string(i), 4, "0")}-xxxxxxxx", "Team #{i}"])
end
team_ids = Bench.SqliteRepo.query!("SELECT id FROM teams ORDER BY id") |> Map.get(:rows) |> Enum.map(&hd/1)
for i <- 0..4999 do
  team_id = Enum.at(team_ids, rem(i, length(team_ids)))
  Bench.SqliteRepo.query!("INSERT INTO users (email, name, team_id) VALUES (?, ?, ?)", ["user#{i}@example.com", "User #{i}", team_id])
  Bench.SqliteRepo.query!("INSERT INTO sites (domain, team_id) VALUES (?, ?)", ["site#{i}.example.com", team_id])
end
user_rows = Bench.SqliteRepo.query!("SELECT id, team_id FROM users ORDER BY id") |> Map.get(:rows)
for [uid, tid] <- user_rows do
  Bench.SqliteRepo.query!("INSERT OR IGNORE INTO team_memberships (team_id, user_id, role) VALUES (?, ?, 'viewer')", [tid, uid])
end
Bench.SqliteRepo.query!("COMMIT")
IO.puts("  SQLite seeded")

# Postgres is already seeded by Bun bench (5000 rows). Verify count
pg_count = Bench.PgRepo.one(from s in "sites", select: count(s.id))
IO.puts("  PG sites count: #{pg_count} (already seeded by Bun bench, reusing)")

# ── Define workload fns (Ecto) ──
defmodule Work do
  import Ecto.Query
  def sqlite_site_by_domain(k), do: Bench.SqliteRepo.one(from s in Bench.Site, where: s.domain == ^"site#{k}.example.com", limit: 1)
  def pg_site_by_domain(k), do: Bench.PgRepo.one(from s in Bench.Site, where: s.domain == ^"site#{k}.example.com", limit: 1)

  def sqlite_user_by_email(k), do: Bench.SqliteRepo.one(from u in Bench.User, join: t in assoc(u, :team), where: u.email == ^"user#{k}@example.com", select: %{email: u.email, team_name: t.name}, limit: 1)
  def pg_user_by_email(k), do: Bench.PgRepo.one(from u in Bench.User, join: t in assoc(u, :team), where: u.email == ^"user#{k}@example.com", select: %{email: u.email, team_name: t.name}, limit: 1)

  def sqlite_sites_by_team(k), do: Bench.SqliteRepo.all(from s in Bench.Site, where: s.team_id == ^(rem(k, 500)+1), order_by: s.domain, limit: 20)
  def pg_sites_by_team(k), do: Bench.PgRepo.all(from s in Bench.Site, where: s.team_id == ^(rem(k, 500)+1), order_by: s.domain, limit: 20)
end

# Warmup
IO.puts("\n== Warmup 500 ==")
for i <- 0..499 do
  k = rem(i, 5000)
  Work.sqlite_site_by_domain(k)
  Work.pg_site_by_domain(k)
end

# ── Benchee single-concurrency ──
IO.puts("\n== Benchee (single concurrency, Ecto overhead) ==")
Benchee.run(
  %{
    "sqlite site by domain" => fn -> Work.sqlite_site_by_domain(Enum.random(0..4999)) end,
    "pg site by domain" => fn -> Work.pg_site_by_domain(Enum.random(0..4999)) end,
    "sqlite user JOIN team" => fn -> Work.sqlite_user_by_email(Enum.random(0..4999)) end,
    "pg user JOIN team" => fn -> Work.pg_user_by_email(Enum.random(0..4999)) end,
    "sqlite list sites by team" => fn -> Work.sqlite_sites_by_team(Enum.random(0..499)) end,
    "pg list sites by team" => fn -> Work.pg_sites_by_team(Enum.random(0..499)) end
  },
  time: 5,
  warmup: 2,
  print: [benchmarking: true, configuration: false]
)

# ── Custom concurrency harness ──
defmodule Harness do
  def percentile(list, p) do
    sorted = Enum.sort(list)
    idx = trunc(length(sorted) * p)
    Enum.at(sorted, idx)
  end

  def run(name, sqlite_fn, pg_fn, concurrency, n \\ 5000) do
    # sqlite
    {sqlite_time, sqlite_lat} = :timer.tc(fn ->
      1..concurrency
      |> Task.async_stream(fn _ ->
        for i <- 0..div(n, concurrency)-1 do
          k = rem(i, 5000)
          t0 = System.monotonic_time(:microsecond)
          sqlite_fn.(k)
          System.monotonic_time(:microsecond) - t0
        end
      end, max_concurrency: concurrency, timeout: 30_000)
      |> Enum.flat_map(fn {:ok, v} -> v end)
    end)
    sqlite_qps = trunc(n / (sqlite_time / 1_000_000))
    sqlite_p50 = percentile(sqlite_lat, 0.5) / 1000
    sqlite_p95 = percentile(sqlite_lat, 0.95) / 1000
    sqlite_p99 = percentile(sqlite_lat, 0.99) / 1000

    # pg
    {pg_time, pg_lat} = :timer.tc(fn ->
      1..concurrency
      |> Task.async_stream(fn _ ->
        for i <- 0..div(n, concurrency)-1 do
          k = rem(i, 5000)
          t0 = System.monotonic_time(:microsecond)
          pg_fn.(k)
          System.monotonic_time(:microsecond) - t0
        end
      end, max_concurrency: concurrency, timeout: 30_000)
      |> Enum.flat_map(fn {:ok, v} -> v end)
    end)
    pg_qps = trunc(n / (pg_time / 1_000_000))
    pg_p50 = percentile(pg_lat, 0.5) / 1000
    pg_p95 = percentile(pg_lat, 0.95) / 1000
    pg_p99 = percentile(pg_lat, 0.99) / 1000

    speedup = sqlite_qps / max(pg_qps, 1)
    IO.puts("#{name} c=#{concurrency} | SQLite #{sqlite_qps} qps p95=#{Float.round(sqlite_p95, 3)}ms | PG #{pg_qps} qps p95=#{Float.round(pg_p95, 3)}ms | x#{Float.round(speedup, 2)}  (sqlite p50 #{Float.round(sqlite_p50,3)} p99 #{Float.round(sqlite_p99,3)} | pg p50 #{Float.round(pg_p50,3)} p99 #{Float.round(pg_p99,3)})")
    {sqlite_qps, pg_qps, speedup}
  end
end

IO.puts("\n== Concurrency sweep (Ecto, Task.async_stream) MEASURE=5000 ==")
for c <- [1, 10, 50] do
  Harness.run("Q1 site by domain", &Work.sqlite_site_by_domain/1, &Work.pg_site_by_domain/1, c)
end
for c <- [1, 10, 50] do
  Harness.run("Q2 user JOIN", &Work.sqlite_user_by_email/1, &Work.pg_user_by_email/1, c)
end
for c <- [1, 10, 50] do
  Harness.run("Q3 list by team", &Work.sqlite_sites_by_team/1, &Work.pg_sites_by_team/1, c)
end

# Mixed 95/5
IO.puts("\n== Q4 mixed 95% read 5% write (sequential, 2000 ops) ==")
sqlite_lat = for i <- 0..1999 do
  t0 = System.monotonic_time(:microsecond)
  if rem(i, 20) == 0 do
    Bench.SqliteRepo.query!("UPDATE sites SET timezone = ? WHERE id = ?", ["Asia/Jakarta", rem(i, 5000)+1])
  else
    Work.sqlite_site_by_domain(rem(i*7, 5000))
  end
  System.monotonic_time(:microsecond) - t0
end
pg_lat = for i <- 0..1999 do
  t0 = System.monotonic_time(:microsecond)
  if rem(i, 20) == 0 do
    Bench.PgRepo.query!("UPDATE sites SET timezone = $1 WHERE id = $2", ["Asia/Jakarta", rem(i, 5000)+1])
  else
    Work.pg_site_by_domain(rem(i*7, 5000))
  end
  System.monotonic_time(:microsecond) - t0
end
IO.puts("  SQLite p50 #{Harness.percentile(sqlite_lat,0.5)/1000}ms p95 #{Harness.percentile(sqlite_lat,0.95)/1000}ms p99 #{Harness.percentile(sqlite_lat,0.99)/1000}ms")
IO.puts("  PG     p50 #{Harness.percentile(pg_lat,0.5)/1000}ms p95 #{Harness.percentile(pg_lat,0.95)/1000}ms p99 #{Harness.percentile(pg_lat,0.99)/1000}ms")

IO.puts("\nDone")

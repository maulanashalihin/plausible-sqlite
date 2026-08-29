import Config
config :logger, level: :warning
config :bench, Bench.SqliteRepo,
  database: "/tmp/bench_elixir.sqlite3",
  journal_mode: :wal,
  synchronous: :normal,
  cache_size: -64000,
  temp_store: :memory,
  pool_size: 10,
  log: false
config :bench, Bench.PgRepo,
  username: "ubuntu",
  password: "bench",
  hostname: "127.0.0.1",
  port: 5432,
  database: "bench_plausible",
  pool_size: 50,
  queue_target: 500,
  queue_interval: 2000,
  log: false

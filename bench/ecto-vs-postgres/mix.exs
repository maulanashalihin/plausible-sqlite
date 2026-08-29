defmodule Bench.MixProject do
  use Mix.Project

  def project do
    [
      app: :bench,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Bench.Application, []}]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13.2"},
      {:ecto_sqlite3, "~> 0.23"},
      {:postgrex, "~> 0.20"},
      {:benchee, "~> 1.3"}
    ]
  end
end

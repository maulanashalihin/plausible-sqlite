defmodule Mix.Tasks.CleanPostgres do
  @moduledoc false
  @shortdoc "Truncate all tables in the SQLite database"

  use Mix.Task

  alias Plausible.Repo

  def run(_) do
    case Plausible.Repo.start_link(pool_size: 1, log: false) do
      {:ok, _} -> :pass
      {:error, {:already_started, _pid}} -> :pass
      {:error, _} = error -> throw(error)
    end

    %{rows: rows} =
      Repo.query!(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
      )

    tables = Enum.map(rows, fn [table] -> table end)

    Enum.each(tables -- ["schema_migrations"], fn table ->
      Repo.query!("DELETE FROM #{table}")
    end)
  after
    Plausible.Repo.stop(500)
  end
end

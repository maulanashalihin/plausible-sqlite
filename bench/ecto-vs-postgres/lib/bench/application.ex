defmodule Bench.Application do
  use Application
  def start(_type, _args) do
    children = [Bench.SqliteRepo, Bench.PgRepo]
    Supervisor.start_link(children, strategy: :one_for_one, name: Bench.Supervisor)
  end
end

defmodule Bench.SqliteRepo do
  use Ecto.Repo, otp_app: :bench, adapter: Ecto.Adapters.SQLite3
end

defmodule Bench.PgRepo do
  use Ecto.Repo, otp_app: :bench, adapter: Ecto.Adapters.Postgres
end

defmodule Bench.Team do
  use Ecto.Schema
  schema "teams" do
    field :identifier, :string
    field :name, :string
    timestamps()
  end
end

defmodule Bench.User do
  use Ecto.Schema
  schema "users" do
    field :email, :string
    field :name, :string
    belongs_to :team, Bench.Team
    timestamps()
  end
end

defmodule Bench.Site do
  use Ecto.Schema
  schema "sites" do
    field :domain, :string
    field :timezone, :string, default: "Etc/UTC"
    belongs_to :team, Bench.Team
    timestamps()
  end
end

defmodule Bench.TeamMembership do
  use Ecto.Schema
  schema "team_memberships" do
    field :role, :string, default: "viewer"
    belongs_to :team, Bench.Team
    belongs_to :user, Bench.User
  end
end

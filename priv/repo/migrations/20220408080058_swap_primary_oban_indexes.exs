defmodule Plausible.Repo.Migrations.SwapPrimaryObanIndexes do
  use Ecto.Migration



  def change do
    create_if_not_exists index(
                           :oban_jobs,
                           [:state, :queue, :priority, :scheduled_at, :id]
                         )

    drop_if_exists index(
                     :oban_jobs,
                     [:queue, :state, :priority, :scheduled_at, :id]
                   )

  end
end

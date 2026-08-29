defmodule Plausible.Ecto.Types.FeatureArray do
  @moduledoc """
  Stores a list of Plausible.Billing.Ecto.Feature as JSON text in SQLite.
  Replaces PostgreSQL's `{:array, Plausible.Billing.Ecto.Feature}` type.
  """

  use Ecto.Type

  alias Plausible.Billing.Ecto.Feature

  def type, do: :string

  def cast(list) when is_list(list) do
    {:ok, Enum.map(list, &cast_feature/1)}
  end

  def cast(_), do: :error

  defp cast_feature(mod) when is_atom(mod), do: mod
  defp cast_feature(str) when is_binary(str), do: Feature.cast(str) |> elem(1)

  def load(nil), do: {:ok, nil}
  def load(""), do: {:ok, []}

  def load(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, list} when is_list(list) ->
        features = Enum.map(list, fn str -> Feature.load(str) |> elem(1) end)
        {:ok, features}

      _ ->
        {:ok, []}
    end
  end

  def load(list) when is_list(list) do
    {:ok, Enum.map(list, fn str -> Feature.load(str) |> elem(1) end)}
  end

  def dump(nil), do: {:ok, nil}

  def dump(list) when is_list(list) do
    strings = Enum.map(list, fn mod -> Feature.dump(mod) |> elem(1) end)
    Jason.encode(strings)
  end

  def dump(_), do: :error
end

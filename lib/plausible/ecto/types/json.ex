defmodule Plausible.Ecto.Types.Json do
  @moduledoc """
  Stores a map as JSON text in SQLite. Replaces PostgreSQL's :map type
  which is not natively supported by Ecto.Adapters.SQLite3.
  """

  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when is_map(value), do: {:ok, value}
  def cast(value) when is_binary(value), do: {:ok, Jason.decode(value)}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  @impl true
  def dump(value) when is_map(value), do: {:ok, Jason.encode!(value)}
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  @impl true
  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end

  @impl true
  def load(nil), do: {:ok, nil}

  @impl true
  def load(value) when is_map(value), do: {:ok, value}

  @impl true
  def embed_as(_), do: :dump

  @impl true
  def equal?(a, b), do: a == b
end

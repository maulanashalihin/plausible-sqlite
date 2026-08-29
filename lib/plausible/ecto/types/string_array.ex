defmodule Plausible.Ecto.Types.StringArray do
  @moduledoc """
  Stores a list of strings as JSON text in SQLite.
  Replaces PostgreSQL's `{:array, :string}` type.
  """

  use Ecto.Type

  def type, do: :string

  def cast(list) when is_list(list), do: {:ok, list}
  def cast(value) when is_binary(value), do: {:ok, [value]}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def load(nil), do: {:ok, nil}
  def load(""), do: {:ok, []}

  def load(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> {:ok, []}
    end
  end

  def load(list) when is_list(list), do: {:ok, list}

  def dump(nil), do: {:ok, nil}
  def dump(list) when is_list(list), do: Jason.encode(list)
  def dump(_), do: :error
end

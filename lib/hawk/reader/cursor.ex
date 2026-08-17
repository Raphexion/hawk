defmodule Hawk.Reader.Cursor do
  @moduledoc false

  @version 1

  def configured?, do: is_binary(Application.get_env(:hawk, :cursor_secret))

  @spec encode(keyword(atom()), struct()) :: String.t()
  def encode(sort, model) do
    payload = {@version, sort, Enum.map(sort, fn {_direction, field} -> Map.fetch!(model, field) end)}

    Plug.Crypto.MessageVerifier.sign(:erlang.term_to_binary(payload), secret())
  end

  @spec decode!(String.t(), keyword(atom()), module()) :: [term()]
  def decode!(cursor, sort, schema) when is_binary(cursor) do
    case Plug.Crypto.MessageVerifier.verify(cursor, secret()) do
      {:ok, encoded} -> decode_payload!(encoded, sort, schema)
      :error -> raise ArgumentError, "invalid or stale page[after] cursor"
    end
  end

  def decode!(_cursor, _sort, _schema), do: raise(ArgumentError, "page[after] must be a string")

  defp decode_payload!(encoded, sort, schema) do
    payload =
      try do
        :erlang.binary_to_term(encoded, [:safe])
      rescue
        ArgumentError -> :invalid
      end

    case payload do
      {@version, ^sort, values} when is_list(values) and length(values) == length(sort) ->
        Enum.zip_with(sort, values, fn {_direction, field}, value -> cast!(schema, field, value) end)

      _other ->
        raise ArgumentError, "invalid or stale page[after] cursor"
    end
  end

  defp secret do
    Application.get_env(:hawk, :cursor_secret) ||
      raise ArgumentError, "cursor pagination is not configured"
  end

  defp cast!(schema, field, value) do
    case Ecto.Type.cast(schema.__schema__(:type, field), value) do
      {:ok, cast} -> cast
      :error -> raise ArgumentError, "invalid page[after] value for #{inspect(field)}"
    end
  end
end

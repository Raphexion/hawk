defmodule Hawk.JsonApi do
  @moduledoc """
  JSON:API metadata and documentation helpers.

  This module starts with documentation/schema generation from `Hawk.Model`
  declarations. Runtime request/response helpers can build on the same metadata.
  """

  def openapi_schema(model) when is_atom(model) do
    json_api = model.__hawk_json_api__()

    %{
      "type" => "object",
      "description" => Map.get(json_api, :doc),
      "properties" => properties(json_api)
    }
  end

  defp properties(json_api) do
    json_api
    |> Map.take([:attributes, :relationships])
    |> Map.values()
    |> Enum.reduce(%{}, &Map.merge(&2, openapi_properties(&1)))
  end

  defp openapi_properties(fields) do
    Map.new(fields, fn {name, metadata} ->
      {to_string(name), openapi_property(metadata)}
    end)
  end

  defp openapi_property(metadata) do
    %{}
    |> put_optional("description", metadata, :doc)
    |> put_optional("example", metadata, :example)
  end

  defp put_optional(target, key, source, source_key) do
    case Map.fetch(source, source_key) do
      {:ok, value} -> Map.put(target, key, value)
      :error -> target
    end
  end
end

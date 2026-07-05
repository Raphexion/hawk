defmodule Hawk.JsonApi do
  @moduledoc """
  JSON:API metadata and documentation helpers.

  This module starts with documentation/schema generation from `Hawk.Model`
  declarations. Runtime request/response helpers can build on the same metadata.
  """

  def request_options(params) when is_map(params) do
    []
    |> put_request_option(:page, parse_page(Map.get(params, "page", %{})), %{})
    |> put_request_option(:preloads, parse_include(Map.get(params, "include")), [])
    |> put_sort(Map.get(params, "sort"))
  end

  def openapi_index_operation(model) when is_atom(model) do
    %{
      parameters: [
        %{name: "sort", schema: %{enum: sort_values(model)}},
        %{name: "page[size]", schema: %{type: "integer", minimum: 0}}
      ]
    }
  end

  def openapi_schema(model) when is_atom(model) do
    json_api = model.__hawk_json_api__()

    %{
      "type" => "object",
      "description" => Map.get(json_api, :doc),
      "properties" => properties(json_api)
    }
  end

  defp put_request_option(opts, _key, value, value), do: opts
  defp put_request_option(opts, key, value, _empty), do: Keyword.put(opts, key, value)

  defp put_sort(opts, nil), do: opts
  defp put_sort(opts, ""), do: opts

  defp put_sort(opts, "-" <> column) do
    Keyword.put(
      opts,
      :page,
      Map.merge(Keyword.get(opts, :page, %{}), %{column: String.to_atom(column), dir: :desc})
    )
  end

  defp put_sort(opts, column) do
    Keyword.put(
      opts,
      :page,
      Map.merge(Keyword.get(opts, :page, %{}), %{column: String.to_atom(column), dir: :asc})
    )
  end

  defp parse_page(page) do
    case Map.get(page, "size") do
      nil -> %{}
      size when is_integer(size) -> %{size: size}
      size when is_binary(size) -> %{size: String.to_integer(size)}
    end
  end

  defp parse_include(nil), do: []
  defp parse_include(""), do: []

  defp parse_include(include) when is_binary(include) do
    include
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  defp sort_values(model) do
    model
    |> reader_module()
    |> sort_keys()
    |> Enum.flat_map(fn key -> [to_string(key), "-#{key}"] end)
  end

  defp reader_module(model), do: Module.concat(model.__hawk_resource__(), Reader)

  defp sort_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :sort_keys, 0) do
      reader.sort_keys() |> Enum.sort()
    else
      [:id]
    end
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

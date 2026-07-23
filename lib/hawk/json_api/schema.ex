defmodule Hawk.JsonApi.Schema do
  @moduledoc """
  Resolves the external JSON:API shape of a Hawk resource.

  This is the shared dependency for `Hawk.JsonApi.Document` (rendering) and
  `Hawk.JsonApi.Request` (parsing/validation): it answers "what does this
  resource look like from the outside?" — type, attributes, relationships, and
  writability — and maps external relationship names to schema associations.

  Metadata is discovered from a `Hawk.Resource` facade's JSON:API adapter when
  one exists, falling back to the model-level `__hawk_json_api__/0` declaration.
  Callers may pass `json_api_by_model: %{model => metadata}` to avoid
  re-resolving adapter metadata per record when rendering collections.
  """

  @doc """
  Resolves JSON:API metadata for a model struct or module.

  ## Options

    * `:json_api_by_model` — a `%{model => metadata}` override map, used to
      short-circuit adapter resolution when the caller has already resolved it.
  """
  def metadata(source, opts \\ [])

  def metadata(%module{}, opts), do: metadata(module, opts)

  def metadata(module, opts) when is_atom(module) do
    opts
    |> Keyword.get(:json_api_by_model, %{})
    |> Map.get(module, discovered_metadata(module))
    |> normalize_metadata()
  end

  @doc """
  Returns the Ecto schema module backing a struct.
  """
  def schema_module(%module{}), do: module

  @doc """
  Resolves an external relationship name to its `{name, source}` mapping.

  `name` is the atom key declared in the resource's JSON:API relationships;
  `source` is the schema association the relationship is backed by.
  """
  def relationship_mapping!(json_api, relationship) when is_map(json_api) and is_binary(relationship) do
    allowed_by_name =
      json_api.relationships
      |> Map.new(fn {name, metadata} ->
        {to_string(name), {name, field_source(name, metadata)}}
      end)

    case Map.fetch(allowed_by_name, relationship) do
      {:ok, mapping} -> mapping
      :error -> raise ArgumentError, "unknown relationship #{inspect(relationship)}"
    end
  end

  @doc """
  Resolves an external relationship name to its schema association source.

  Accepts either a binary external name (resolved through `relationship_mapping!/2`)
  or an atom relationship key (read directly from the metadata map).
  """
  def relationship_source!(json_api, name) when is_map(json_api) and is_binary(name) do
    {_name, source} = relationship_mapping!(json_api, name)
    source
  end

  def relationship_source!(json_api, name) when is_map(json_api) and is_atom(name) do
    field_source(name, Map.fetch!(json_api.relationships, name))
  end

  @doc """
  Resolves a relationship name on a model (struct or module) to its source.

  This is the member-route entry point: given a model and the relationship
  segment of a `GET /:id/:relationship` or `GET /:id/relationships/:relationship`
  request, returns the schema association to preload.
  """
  def relationship_key!(model, relationship, opts \\ [])

  def relationship_key!(model, relationship, opts) when is_struct(model) do
    relationship_key!(schema_module(model), relationship, opts)
  end

  def relationship_key!(model, relationship, opts) when is_atom(model) and is_binary(relationship) do
    {_name, source} = relationship_mapping!(metadata(model, opts), relationship)
    source
  end

  defp discovered_metadata(module) do
    with true <- function_exported?(module, :__hawk_resource__, 0),
         resource <- module.__hawk_resource__(),
         {:module, ^resource} <- Code.ensure_compiled(resource),
         true <- function_exported?(resource, :__hawk_resource__, 1),
         json_api when json_api not in [false, nil] <- resource.__hawk_resource__(:json_api),
         {:module, ^json_api} <- Code.ensure_compiled(json_api),
         true <- function_exported?(json_api, :__hawk_json_api__, 0) do
      json_api.__hawk_json_api__()
    else
      _other -> module.__hawk_json_api__()
    end
  end

  defp normalize_metadata(metadata) do
    Map.merge(%{attributes: %{}, relationships: %{}, creatable: [], updatable: []}, metadata)
  end

  defp field_source(name, metadata), do: Map.get(metadata, :source, name)
end

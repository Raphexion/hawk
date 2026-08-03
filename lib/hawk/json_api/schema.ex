defmodule Hawk.JsonApi.Schema do
  @moduledoc """
  Resolves the external JSON:API shape of a Hawk resource.

  This is the shared dependency for `Hawk.JsonApi.Document` (rendering) and
  `Hawk.JsonApi.Request` (parsing/validation): it answers "what does this
  resource look like from the outside?" — type, attributes, relationships, and
  writability — and maps external relationship names to schema associations.

  The sibling JSON:API adapter (`MyApp.Courses.JsonApi`) is the single source of
  a resource's external shape. It is discovered by convention from the model's
  resource: a `Hawk.Resource` facade exposes its adapter through
  `__hawk_resource__(:json_api)`, and the model's `__hawk_resource__/0` resolves
  the facade by convention. When a resource has no JSON:API surface (no adapter),
  a type-only default is returned so relationship type resolution and error
  messages keep working.

  `metadata/1` is memoized in `:persistent_term` (keyed by module) in `:prod`
  and `:test`, since the JSON:API shape is invariant after compile. It is left
  uncached in `:dev` so adapter edits in a running consumer dev server stay
  fresh without a restart.
  """

  @metadata_cache_key {__MODULE__, :metadata}
  @metadata_cache_enabled Mix.env() in [:prod, :test]

  @doc """
  Resolves JSON:API metadata for a model struct or module.
  """
  def metadata(source)

  def metadata(%module{}), do: metadata(module)

  def metadata(module) when is_atom(module) do
    metadata_cached(module, @metadata_cache_enabled)
  end

  def metadata_cached(module, true) do
    key = {@metadata_cache_key, module}

    case :persistent_term.get(key, :not_found) do
      :not_found ->
        result = compute_metadata(module)
        :persistent_term.put(key, result)
        result

      cached ->
        cached
    end
  end

  def metadata_cached(module, false) do
    compute_metadata(module)
  end

  defp compute_metadata(module), do: module |> discovered_metadata() |> normalize_metadata()

  @doc """
  Returns the Ecto schema module backing a struct, or the module itself.
  """
  def schema_module(%module{}), do: module
  def schema_module(module) when is_atom(module), do: module

  @doc """
  Resolves the JSON:API error `source.pointer` for an internal model field.

  Writer changeset errors are keyed by internal Ecto fields, but a client sent
  external JSON:API attribute/relationship names. This maps an internal field
  back to the external name so error pointers stay client-visible:

    * an attribute whose `source:` (or own name) matches the field renders as
      `/data/attributes/{external}`
    * a `belongs_to` foreign key renders as `/data/relationships/{external}`
    * a field with no external surface (e.g. an internal-only filter column)
      falls back to `/data/attributes/{field}`, preserving prior behavior

  This closes the gap where `attribute(:name, source: :title)` rendered a
  validation error at `/data/attributes/title` — a pointer the client never
  sent because the spec exposes the field as `name`.
  """
  @spec external_pointer(struct() | module(), atom()) :: String.t()
  def external_pointer(model, field) when is_atom(field) do
    module = schema_module(model)
    json_api = metadata(module)

    case attribute_external_name(json_api, field) do
      {:ok, name} -> "/data/attributes/#{name}"
      :error -> relationship_external_pointer(module, json_api, field)
    end
  end

  defp attribute_external_name(json_api, field) do
    Enum.find_value(json_api.attributes, fn {name, metadata} ->
      source = Map.get(metadata, :source, name)
      if source == field, do: name
    end)
    |> case do
      nil -> :error
      name -> {:ok, name}
    end
  end

  defp relationship_external_pointer(module, json_api, field) do
    Enum.find_value(json_api.relationships, fn {name, metadata} ->
      source = Map.get(metadata, :source, name)
      association = module.__schema__(:association, source)

      case association do
        %Ecto.Association.BelongsTo{owner_key: ^field} -> name
        _ -> nil
      end
    end)
    |> case do
      nil -> "/data/attributes/#{field}"
      name -> "/data/relationships/#{name}"
    end
  end

  @doc """
  Resolves an external relationship name to its `{name, source}` mapping.

  Returns `{:ok, mapping}` or `:error` when the external name is not declared.
  `name` is the atom key declared in the resource's JSON:API relationships;
  `source` is the schema association the relationship is backed by.
  """
  def relationship_mapping(json_api, relationship) when is_map(json_api) and is_binary(relationship) do
    json_api.relationships
    |> Map.new(fn {name, metadata} ->
      {to_string(name), {name, field_source(name, metadata)}}
    end)
    |> Map.fetch(relationship)
  end

  @doc """
  Resolves an external relationship name, raising when it is not declared.
  """
  def relationship_mapping!(json_api, relationship) when is_map(json_api) and is_binary(relationship) do
    case relationship_mapping(json_api, relationship) do
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
  def relationship_key!(model, relationship)

  def relationship_key!(model, relationship) when is_struct(model) do
    relationship_key!(schema_module(model), relationship)
  end

  def relationship_key!(model, relationship) when is_atom(model) and is_binary(relationship) do
    {_name, source} = relationship_mapping!(metadata(model), relationship)
    source
  end

  @doc """
  Resolves the identity field for a model struct or module.

  The identity field is the model attribute used as the JSON:API `id` and the
  member-lookup key (default `:id`). It is declared on the resource facade with
  `use Hawk.Resource, model: ..., identity: :field`. Resources whose backing
  table has no `:id` (e.g. database views keyed by another column) declare a
  different identity so every adapter stops assuming `:id`.
  """
  @spec identity(struct() | module()) :: atom()
  def identity(%module{}), do: identity(module)

  def identity(module) when is_atom(module) do
    case Hawk.Resource.Convention.resource_module(module) do
      resource when is_atom(resource) -> identity_for_facade(resource)
    end
  end

  @doc """
  Resolves the identity field declared on a resource facade.

  Falls back to `:id` when the facade does not declare one (e.g. a model without
  a Hawk resource).
  """
  @spec identity_for_facade(module()) :: atom()
  def identity_for_facade(resource) when is_atom(resource) do
    Code.ensure_compiled(resource)

    if function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(:identity) do
        nil -> :id
        identity when is_atom(identity) -> identity
      end
    else
      :id
    end
  end

  defp discovered_metadata(module) do
    Code.ensure_compiled(module)

    cond do
      function_exported?(module, :__hawk_json_api__, 0) ->
        module.__hawk_json_api__()

      function_exported?(module, :__hawk_resource__, 0) ->
        resource = module.__hawk_resource__()
        adapter = resolve_adapter(resource)

        if adapter do
          adapter.__hawk_json_api__()
        else
          default_metadata(resource)
        end

      true ->
        default_metadata(module)
    end
  end

  defp resolve_adapter(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(:json_api) do
        false -> nil
        adapter -> adapter
      end
    else
      nil
    end
  end

  defp default_metadata(resource) do
    name =
      resource
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    %{type: name, attributes: %{}, relationships: %{}, creatable: [], updatable: []}
  end

  defp normalize_metadata(metadata) do
    Map.merge(%{attributes: %{}, relationships: %{}, creatable: [], updatable: []}, metadata)
  end

  defp field_source(name, metadata), do: Map.get(metadata, :source, name)
end

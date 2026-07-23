defmodule Hawk.JsonApi.Document do
  @moduledoc """
  Renders JSON:API documents from Hawk resources.

  Document rendering is pure data: given a model (or collection) and render
  options, it produces the JSON:API resource objects, relationships, included
  resources, links, and pagination meta. The external shape of each resource
  is resolved through `Hawk.JsonApi.Schema.metadata/2`, so included/related
  resources discover their adapter metadata the same way the root does.

  ## Options

    * `:preloads` — the preload tree to render as `included` resources.
    * `:links` — when true, emits `self`/relationship links.
    * `:self` — overrides the collection `self` link.
    * `:context` — request context passed to attribute resolvers (e.g. locale).
    * `:page` — page map; when present, emits `meta.page`.
  """

  alias Hawk.JsonApi.Schema

  def document(models, opts \\ [])

  def document(models, opts) when is_list(models) do
    %{data: Enum.map(models, &resource_object(&1, opts))}
    |> put_document_links(models, opts)
    |> put_included(models, opts)
    |> put_pagination_meta(models, opts)
  end

  def document(model, opts) when is_struct(model) do
    %{data: resource_object(model, opts)}
    |> put_document_links([model], opts)
    |> put_included([model], opts)
  end

  @doc """
  Renders a `GET /:id/relationships/:relationship` linkage document.
  """
  def relationship_document(model, relationship)
      when is_struct(model) and is_binary(relationship) do
    json_api = Schema.metadata(model)
    {name, source} = Schema.relationship_mapping!(json_api, relationship)
    data = relationship_data(model, source, [source])

    %{
      links: relationship_links(model, json_api, name),
      data: data
    }
  end

  @doc """
  Renders a `GET /:id/:relationship` related-resource document.
  """
  def related_document(model, relationship, opts \\ [])
      when is_struct(model) and is_binary(relationship) do
    {_name, source} = Schema.relationship_mapping!(Schema.metadata(model), relationship)

    case related_value(model, source) do
      models when is_list(models) ->
        document(
          models,
          opts |> Keyword.put(:links, true) |> Keyword.put(:self, collection_path(model, source))
        )

      nil ->
        %{data: nil}

      related ->
        document(related, Keyword.put(opts, :links, true))
    end
  end

  defp resource_object(model, opts) do
    json_api = Schema.metadata(model)

    %{
      type: json_api.type,
      id: to_string(Map.get(model, :id)),
      attributes: resource_attributes(model, json_api, opts),
      relationships: resource_relationships(model, json_api, opts)
    }
    |> put_resource_links(model, json_api, opts)
  end

  defp resource_attributes(model, json_api, opts) do
    Map.new(json_api.attributes, fn {name, metadata} ->
      {name, resource_attribute(model, name, metadata, opts)}
    end)
  end

  defp resource_attribute(model, _name, %{resolver: resolver}, opts)
       when is_function(resolver, 2),
       do: resolver.(model, opts)

  defp resource_attribute(model, _name, %{resolver: resolver}, _opts)
       when is_function(resolver, 1),
       do: resolver.(model)

  defp resource_attribute(model, _name, %{source: source}, _opts) when is_atom(source),
    do: Map.get(model, source)

  defp resource_attribute(model, name, _metadata, _opts), do: Map.get(model, name)

  defp resource_relationships(model, json_api, opts) do
    preloads = Keyword.get(opts, :preloads, [])

    Map.new(json_api.relationships, fn {name, metadata} ->
      source = Map.get(metadata, :source, name)
      relationship = %{data: relationship_data(model, source, preloads)}

      if Keyword.get(opts, :links, false) do
        {name, Map.put(relationship, :links, relationship_links(model, json_api, name))}
      else
        {name, relationship}
      end
    end)
  end

  defp relationship_data(model, name, preloads) do
    association = Schema.schema_module(model).__schema__(:association, name)

    case association.cardinality do
      :one -> belongs_to_identifier(model, association)
      :many -> many_identifiers(Map.get(model, name), preload_requested?(preloads, name))
    end
  end

  defp relationship_links(model, json_api, name) do
    base = resource_path(model, json_api)

    %{
      self: base <> "/relationships/" <> to_string(name),
      related: base <> "/" <> to_string(name)
    }
  end

  defp put_resource_links(resource, model, json_api, opts) do
    if Keyword.get(opts, :links, false) do
      Map.put(resource, :links, %{self: resource_path(model, json_api)})
    else
      resource
    end
  end

  defp put_document_links(document, [first | _models], opts) do
    if Keyword.get(opts, :links, false) do
      Map.put(document, :links, %{self: Keyword.get(opts, :self, document_self_link(first))})
    else
      document
    end
  end

  defp put_document_links(document, [], opts) do
    if Keyword.get(opts, :links, false) do
      Map.put(document, :links, %{self: Keyword.get(opts, :self, "/")})
    else
      document
    end
  end

  defp document_self_link(model) when is_struct(model), do: resource_path(model, Schema.metadata(model))

  defp collection_path(model, relationship) do
    association = Schema.schema_module(model).__schema__(:association, relationship)
    "/" <> Schema.metadata(association.related).type
  end

  defp resource_path(model, json_api) do
    "/" <> json_api.type <> "/" <> to_string(Map.get(model, :id))
  end

  defp belongs_to_identifier(model, association) do
    id = Map.get(model, association.owner_key)
    type = Schema.metadata(association.related).type

    if is_nil(id), do: nil, else: %{type: type, id: to_string(id)}
  end

  defp many_identifiers(_models, false), do: []
  defp many_identifiers(%Ecto.Association.NotLoaded{}, true), do: []
  defp many_identifiers(nil, true), do: []

  defp many_identifiers(models, true),
    do:
      Enum.map(
        models,
        &%{type: Schema.metadata(&1).type, id: to_string(Map.get(&1, :id))}
      )

  defp preload_requested?(preloads, name) do
    Enum.any?(preloads, fn
      ^name -> true
      {^name, _nested} -> true
      _other -> false
    end)
  end

  defp put_included(document, models, opts) do
    included = included_resources(models, Keyword.get(opts, :preloads, []), opts)

    if included == [] do
      document
    else
      Map.put(document, :included, included)
    end
  end

  defp included_resources(models, preloads, opts) do
    models
    |> Enum.flat_map(&included_resources_for_model(&1, preloads, opts))
    |> Enum.uniq_by(&{&1.type, &1.id})
  end

  defp included_resources_for_model(model, preloads, opts) do
    Enum.flat_map(preloads, fn
      name when is_atom(name) ->
        direct_included_resources(model, name, [], opts)

      {name, nested} when is_atom(name) ->
        direct_included_resources(model, name, nested, opts)
    end)
  end

  defp direct_included_resources(model, name, nested, opts) do
    model
    |> related_models(name)
    |> Enum.flat_map(fn related ->
      [resource_object(related, Keyword.put(opts, :preloads, nested))] ++
        included_resources_for_model(related, nested, opts)
    end)
  end

  defp related_models(model, name) do
    case Map.get(model, name) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      models when is_list(models) -> models
      model -> [model]
    end
  end

  defp related_value(model, name) do
    case Map.get(model, name) do
      %Ecto.Association.NotLoaded{} -> nil
      value -> value
    end
  end

  defp put_pagination_meta(document, models, opts) do
    case Keyword.get(opts, :page) do
      nil ->
        document

      page ->
        Map.put(document, :meta, %{
          page: %{
            size: Map.get(page, :size),
            number: Map.get(page, :number, 1),
            count: length(models)
          }
        })
    end
  end
end

defmodule Hawk.OpenApi do
  @moduledoc """
  Composes OpenAPI specifications from Hawk JSON:API resource declarations.
  """

  alias Hawk.JsonApi.Routes

  @doc """
  Composes an OpenAPI 3.1 spec map from the given Hawk resource facades.

  Resources with `json_api: false` are omitted. This is the function behind
  `mix hawk.openapi` and `Hawk.OpenApi.Controller`; call it directly only when
  you need the spec as data.

  ## Options

    * `:title` (required) — the info title. The host app must name its API; Hawk
      does not pick one. OpenAPI requires `info.title`.
    * `:version` — the info version (default `"1.0.0"`).
    * `:license` — the `info.license` object. Accepts a string (rendered as
      `%{name: string}`) or a `%{name: ..., url: ...}` map; omitted when not set.
      Hawk is a library and does not choose a license for the host app.
    * `:servers` — the servers list (default `[%{url: "/"}]`).
    * `:security` — the top-level security list (default `[]`).
    * `:path_prefix` — a prefix applied to every path (default `""`).
  """
  def spec(resources, opts \\ []) when is_list(resources) do
    resources = resources |> Enum.map(&normalize_resource/1) |> Enum.reject(&is_nil/1)

    title =
      Keyword.get(opts, :title) ||
        raise ArgumentError, "Hawk.OpenApi.spec/2 requires :title — the host app must name its API"

    info =
      %{
        title: title,
        version: Keyword.get(opts, :version, "1.0.0")
      }
      |> maybe_put_license(Keyword.get(opts, :license))

    %{
      openapi: "3.1.0",
      info: info,
      servers: Keyword.get(opts, :servers, [%{url: "/"}]),
      security: Keyword.get(opts, :security, []),
      tags: tags(resources),
      paths: paths(resources, Keyword.get(opts, :path_prefix, "")),
      components: %{
        schemas: schemas(resources)
      }
    }
  end

  # `info.license` is the host app's choice, not Hawk's. Accept a name string
  # (rendered as `%{name: ...}`) or a full `%{name: ..., url: ...}` map.
  defp maybe_put_license(info, nil), do: info
  defp maybe_put_license(info, license) when is_binary(license), do: Map.put(info, :license, %{name: license})
  defp maybe_put_license(info, %{name: _} = license), do: Map.put(info, :license, license)

  defp normalize_resource(module) when is_atom(module) do
    Code.ensure_compiled(module)

    if function_exported?(module, :__hawk_resource__, 1) do
      model = module.__hawk_resource__(:model)

      case json_api_metadata!(module) do
        nil ->
          nil

        json_api ->
          %{
            model: model,
            resource: module,
            json_api: json_api,
            capabilities: module.__hawk_resource__(:capabilities)
          }
      end
    end
  end

  defp json_api_metadata!(resource) do
    case resource.__hawk_resource__(:json_api) do
      false -> nil
      json_api -> json_api.__hawk_json_api__()
    end
  end

  defp tags(resources) do
    resources
    |> Enum.map(&tag_object(&1.json_api))
    |> Enum.reject(&is_nil/1)
    |> dedupe_tags()
    |> Enum.sort_by(& &1[:name])
    |> Enum.map(&maybe_put_description/1)
  end

  defp tag_object(json_api) do
    case Map.get(json_api, :tag) do
      nil -> nil
      name -> %{name: name, description: Map.get(json_api, :tag_description)}
    end
  end

  # Multiple resources can share a tag name. Collapse them to one entry per
  # name, preferring an entry that carries a description over one without.
  defp dedupe_tags(tags) do
    tags
    |> Enum.group_by(& &1[:name])
    |> Enum.map(fn {_name, group} ->
      Enum.find(group, &(&1[:description] != nil)) || hd(group)
    end)
  end

  defp maybe_put_description(%{description: nil} = tag), do: Map.delete(tag, :description)
  defp maybe_put_description(tag), do: tag

  defp paths(resources, path_prefix) do
    Enum.reduce(resources, %{}, fn resource, paths ->
      Map.merge(paths, resource_paths(resource, path_prefix))
    end)
  end

  defp resource_paths(resource, path_prefix) do
    resource
    |> Routes.routes(path_prefix: path_prefix)
    |> Enum.flat_map(&operation_entries(resource, &1))
    |> Enum.reduce(%{}, fn {path, method, operation}, paths ->
      Map.update(paths, path, %{method => operation}, &Map.put(&1, method, operation))
    end)
  end

  defp operation_entries(resource, %{action: :action} = route) do
    resource.resource
    |> Hawk.Actions.actions()
    |> Enum.map(fn {name, metadata} ->
      route.path
      |> openapi_path()
      |> String.replace("{action}", name)
      |> then(&{&1, route.method, action_operation(resource, name, metadata)})
    end)
  end

  defp operation_entries(resource, route) do
    [{openapi_path(route.path), route.method, route_operation(resource, route)}]
  end

  defp route_operation(resource, %{action: :index}), do: index_operation(resource)
  defp route_operation(resource, %{action: :show}), do: show_operation(resource)

  defp route_operation(resource, %{action: :create}),
    do: write_operation(resource, :creatable, "Create #{resource_name(resource)}", 201)

  defp route_operation(resource, %{action: :update}) do
    write_operation(resource, :updatable, "Update #{resource_name(resource)}", 200, parameters: [uuid_id_parameter()])
  end

  defp route_operation(resource, %{action: :delete}), do: delete_operation(resource)
  defp route_operation(resource, %{action: :relationship}), do: relationship_operation(resource)
  defp route_operation(resource, %{action: :related}), do: related_operation(resource)

  defp openapi_path(path) do
    Regex.replace(~r/:([a-zA-Z_]+)/, path, "{\\1}")
  end

  defp index_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "list#{pascalize(resource.json_api.type)}",
      summary: "List #{resource.json_api.type}",
      parameters: index_parameters(resource),
      responses: responses(resource, 200, array_schema(resource))
    })
  end

  defp show_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "show#{pascalize(resource.json_api.type)}",
      summary: "Show #{resource_name(resource)}",
      parameters: [show_id_parameter()],
      responses: responses(resource, 200, data_schema(resource))
    })
  end

  defp write_operation(resource, capability, summary, success_status, opts \\ []) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "#{write_verb(capability)}#{pascalize(resource.json_api.type)}",
      summary: summary,
      parameters: Keyword.get(opts, :parameters, []),
      requestBody: request_body(resource, capability),
      responses: responses(resource, success_status, data_schema(resource))
    })
  end

  defp delete_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "delete#{pascalize(resource.json_api.type)}",
      summary: "Delete #{resource_name(resource)}",
      parameters: [uuid_id_parameter()],
      responses: responses(resource, 204, nil)
    })
  end

  defp relationship_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "show#{pascalize(resource.json_api.type)}Relationship",
      summary: "Show #{resource_name(resource)} relationship linkage",
      parameters: [uuid_id_parameter(), relationship_parameter(resource)],
      responses: responses(resource, 200, relationship_document_schema())
    })
  end

  defp related_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "show#{pascalize(resource.json_api.type)}Related",
      summary: "Show #{resource_name(resource)} related resource",
      parameters: [uuid_id_parameter(), relationship_parameter(resource)],
      responses: responses(resource, 200, data_schema(resource))
    })
  end

  defp action_operation(resource, name, metadata) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      operationId: "run#{pascalize(resource.json_api.type)}#{pascalize(name)}",
      summary: "Run #{name} for #{resource_name(resource)}",
      description: metadata[:doc],
      parameters: [uuid_id_parameter()],
      requestBody: action_request_body(metadata),
      responses: responses(resource, 200, data_schema(resource))
    })
  end

  # Builds a PascalCase identifier from a kebab-case JSON:API type or action
  # name (e.g. "course-rosters" -> "CourseRosters", "open-registration" ->
  # "OpenRegistration"). Used for OpenAPI `operationId`s, which must be unique
  # across the spec and are derived from the resource type plus the operation.
  defp pascalize(name) do
    name
    |> String.split("-")
    |> Enum.map_join(&String.capitalize/1)
  end

  defp write_verb(:creatable), do: "create"
  defp write_verb(:updatable), do: "update"

  defp operation_metadata(resource) do
    %{}
    |> put_metadata(resource.json_api, :tag, :tags, &List.wrap/1)
    |> put_metadata(resource.json_api, :group, :"x-resource-group")
    |> Map.put(:"x-resource-type", resource.json_api.type)
  end

  defp index_parameters(resource) do
    [
      include_parameter(resource),
      sort_parameter(resource),
      %{name: "page[size]", in: "query", schema: %{type: "integer", minimum: 0}}
    ]
  end

  defp include_parameter(resource) do
    %{
      name: "include",
      in: "query",
      schema: %{
        type: "string",
        enum: include_values(resource)
      }
    }
  end

  defp sort_parameter(resource) do
    %{
      name: "sort",
      in: "query",
      schema: %{type: "string", enum: sort_values(resource)}
    }
  end

  defp show_id_parameter do
    %{
      name: "id",
      in: "path",
      required: true,
      schema: %{type: "string"},
      description: "Full UUID, or the first 8 hex characters of a UUID (short id) for read-only member lookups."
    }
  end

  defp uuid_id_parameter do
    %{name: "id", in: "path", required: true, schema: %{type: "string", format: "uuid"}}
  end

  defp relationship_parameter(resource) do
    %{
      name: "relationship",
      in: "path",
      required: true,
      schema: %{
        type: "string",
        enum: resource.json_api.relationships |> Map.keys() |> Enum.map(&to_string/1)
      }
    }
  end

  defp request_body(resource, capability) do
    %{
      required: true,
      content: %{
        "application/vnd.api+json" => %{
          schema: write_document_schema(resource, capability)
        }
      }
    }
  end

  defp action_request_body(metadata) do
    %{
      required: true,
      content: %{
        "application/vnd.api+json" => %{
          schema: action_document_schema(metadata)
        }
      }
    }
  end

  defp responses(_resource, 204, nil) do
    %{
      "204" => %{description: "No content"},
      "400" => json_api_content("Invalid JSON:API query parameters", error_document_ref()),
      "403" => json_api_content("Forbidden by Hawk policy", error_document_ref()),
      "404" => json_api_content("Resource not found", error_document_ref()),
      "422" => json_api_content("Validation failed", error_document_ref())
    }
  end

  defp responses(_resource, success_status, success_schema) do
    %{
      Integer.to_string(success_status) => json_api_content(success_description(success_status), success_schema),
      "400" => json_api_content("Invalid JSON:API query parameters", error_document_ref()),
      "403" => json_api_content("Forbidden by Hawk policy", error_document_ref()),
      "404" => json_api_content("Resource not found", error_document_ref()),
      "422" => json_api_content("Validation failed", error_document_ref())
    }
  end

  defp success_description(200), do: "JSON:API response"
  defp success_description(201), do: "JSON:API resource created"

  defp json_api_content(description, schema) do
    %{description: description, content: %{"application/vnd.api+json" => %{schema: schema}}}
  end

  defp data_schema(resource), do: %{type: "object", properties: %{data: schema_ref(resource)}}

  defp relationship_document_schema do
    %{type: "object", properties: %{data: %{type: "object"}}}
  end

  defp array_schema(resource) do
    %{type: "object", properties: %{data: %{type: "array", items: schema_ref(resource)}}}
  end

  defp write_document_schema(resource, capability) do
    %{
      type: "object",
      properties: %{
        data: %{
          type: "object",
          properties: %{
            type: %{type: "string", enum: [resource.json_api.type]},
            attributes: %{type: "object", properties: writable_attributes(resource, capability)},
            relationships: %{
              type: "object",
              properties: writable_relationships(resource, capability)
            }
          }
        }
      }
    }
  end

  defp action_document_schema(metadata) do
    %{
      type: "object",
      properties: %{
        meta: %{
          type: "object",
          properties: action_meta_properties(metadata)
        }
      }
    }
  end

  defp action_meta_properties(metadata) do
    metadata
    |> Map.get(:params, %{})
    |> Map.new(fn {name, field_metadata} ->
      {name, field_schema(Map.get(field_metadata, :type), field_metadata)}
    end)
  end

  defp schemas(resources) do
    resource_schemas = Map.new(resources, &{schema_name(&1), resource_schema(&1)})

    Map.merge(resource_schemas, %{
      JsonApiError: error_schema(),
      JsonApiErrorDocument: error_document_schema()
    })
  end

  defp resource_schema(resource) do
    %{
      type: "object",
      description: Map.get(resource.json_api, :doc),
      "x-resource-group": Map.get(resource.json_api, :group),
      "x-resource-type": resource.json_api.type,
      properties: %{
        type: %{type: "string", enum: [resource.json_api.type]},
        id: %{type: "string"},
        attributes: %{type: "object", properties: attribute_properties(resource)},
        relationships: %{type: "object", properties: relationship_properties(resource)}
      }
    }
  end

  defp attribute_properties(resource) do
    Map.new(resource.json_api.attributes, fn {name, metadata} ->
      {name, field_schema(attribute_type(resource, name, metadata), metadata)}
    end)
  end

  defp relationship_properties(resource) do
    Map.new(resource.json_api.relationships, fn {name, metadata} ->
      {name, relationship_schema(resource, name, metadata)}
    end)
  end

  defp writable_attributes(resource, capability) do
    allowed = Map.fetch!(resource.json_api, capability)

    resource.json_api.attributes
    |> Map.take(allowed)
    |> Map.new(fn {name, metadata} ->
      {name, field_schema(attribute_type(resource, name, metadata), metadata)}
    end)
  end

  defp writable_relationships(resource, capability) do
    allowed = Map.fetch!(resource.json_api, capability)

    resource.json_api.relationships
    |> Map.take(allowed)
    |> Map.new(fn {name, metadata} ->
      {name, relationship_schema(resource, name, metadata)}
    end)
  end

  defp attribute_type(resource, name, metadata) do
    source = Map.get(metadata, :source, name)
    resource.model.__schema__(:type, source)
  end

  defp relationship_schema(resource, name, metadata) do
    source = Map.get(metadata, :source, name)

    case resolve_relationship_target(resource, source) do
      nil ->
        # Association not resolvable (e.g. a projection over an internal
        # shape); fall back to a generic object so the spec still renders.
        field_schema(:map, metadata)

      {related_type, cardinality} ->
        resource_identifier_schema(related_type, cardinality)
        |> put_optional(:description, metadata, :doc)
        |> put_relationship_example(metadata)
    end
  end

  defp resolve_relationship_target(resource, source) do
    case resource.model.__schema__(:association, source) do
      %{related: related, cardinality: cardinality} ->
        {Hawk.JsonApi.Schema.metadata(related).type, cardinality}

      _no_association ->
        nil
    end
  end

  defp resource_identifier_schema(related_type, :one) do
    %{
      type: "object",
      properties: %{
        data: %{
          type: "object",
          properties: %{
            type: %{type: "string", enum: [related_type]},
            id: %{type: "string"}
          }
        }
      }
    }
  end

  defp resource_identifier_schema(related_type, :many) do
    %{
      type: "object",
      properties: %{
        data: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              type: %{type: "string", enum: [related_type]},
              id: %{type: "string"}
            }
          }
        }
      }
    }
  end

  defp field_schema(type, metadata) do
    type
    |> openapi_type()
    |> put_optional(:description, metadata, :doc)
    |> put_optional(:example, metadata, :example)
  end

  defp openapi_type(:integer), do: %{type: "integer"}
  defp openapi_type(:id), do: %{type: "integer"}
  defp openapi_type(:boolean), do: %{type: "boolean"}
  defp openapi_type(:float), do: %{type: "number"}
  defp openapi_type(_type), do: %{type: "string"}

  defp error_document_schema do
    %{
      type: "object",
      properties: %{
        errors: %{type: "array", items: %{"$ref": "#/components/schemas/JsonApiError"}}
      }
    }
  end

  defp error_document_ref, do: %{"$ref": "#/components/schemas/JsonApiErrorDocument"}

  defp error_schema do
    %{
      type: "object",
      properties: %{
        status: %{type: "string"},
        code: %{type: "string"},
        title: %{type: "string"},
        detail: %{type: "string"}
      }
    }
  end

  defp schema_ref(resource), do: %{"$ref": "#/components/schemas/#{schema_name(resource)}"}

  defp schema_name(resource) do
    resource.model |> Module.split() |> List.last() |> Kernel.<>("Resource") |> String.to_atom()
  end

  defp resource_name(resource), do: resource.json_api.type |> String.trim_trailing("s")

  defp include_values(resource) do
    resource.model
    |> include_values(resource.resource |> Module.concat(Reader), 2, [])
    |> Enum.map(&external_include_value(resource, &1))
    |> Enum.sort()
  end

  defp external_include_value(resource, include) do
    [first | rest] = String.split(include, ".")
    external = external_relationship_name(resource, String.to_existing_atom(first))
    Enum.join([external | rest], ".")
  end

  defp external_relationship_name(resource, source) do
    resource.json_api.relationships
    |> Enum.find_value(source, fn {name, metadata} ->
      if Map.get(metadata, :source, name) == source, do: name
    end)
    |> to_string()
  end

  defp include_values(schema, reader, depth, seen) do
    if {schema, reader} in seen do
      []
    else
      seen = [{schema, reader} | seen]

      reader
      |> preload_keys()
      |> Enum.flat_map(fn key ->
        nested = nested_include_values(schema, reader, key, depth, seen)
        [to_string(key) | Enum.map(nested, &"#{key}.#{&1}")]
      end)
    end
  end

  defp nested_include_values(_schema, _reader, _key, 1, _seen), do: []

  defp nested_include_values(schema, reader, key, depth, seen) do
    with {:ok, association} <- fetch_association(schema, key),
         {:ok, nested_reader} <- fetch_preload_reader(schema, reader, key) do
      include_values(association.related, nested_reader, depth - 1, seen)
    else
      :error -> []
    end
  end

  defp preload_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_keys, 0) do
      reader.preload_keys() |> Enum.sort()
    else
      []
    end
  end

  defp fetch_association(schema, key) do
    case schema.__schema__(:association, key) do
      nil -> :error
      association -> {:ok, association}
    end
  end

  defp fetch_preload_reader(schema, reader, key) do
    reader_readers =
      if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_readers, 0) do
        reader.preload_readers()
      else
        %{}
      end

    case Map.fetch(reader_readers, key) do
      {:ok, nested_reader} -> {:ok, nested_reader}
      :error -> schema.__hawk_association_reader__(key)
    end
  end

  defp sort_values(resource) do
    resource.resource
    |> Module.concat(Reader)
    |> sort_keys()
    |> Enum.flat_map(fn key -> [to_string(key), "-#{key}"] end)
  end

  defp sort_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :sort_keys, 0) do
      reader.sort_keys() |> Enum.sort()
    else
      [:id]
    end
  end

  defp put_metadata(target, source, source_key, target_key, transform \\ & &1) do
    case Map.fetch(source, source_key) do
      {:ok, nil} -> target
      {:ok, value} -> Map.put(target, target_key, transform.(value))
      :error -> target
    end
  end

  defp put_optional(target, key, source, source_key) do
    case Map.fetch(source, source_key) do
      {:ok, value} -> Map.put(target, key, value)
      :error -> target
    end
  end

  # A JSON:API relationship object wraps its identifiers under `data`, so the
  # user-facing `example:` describes the `data` payload (a single identifier
  # object for to-one, an array of them for to-many). The OpenAPI example must
  # be nested under `data` to match the emitted schema and validate against
  # it; emitting it at the wrapper level produces stray `id`/`type` properties.
  defp put_relationship_example(schema, metadata) do
    case Map.fetch(metadata, :example) do
      {:ok, example} -> Map.put(schema, :example, %{data: example})
      :error -> schema
    end
  end
end

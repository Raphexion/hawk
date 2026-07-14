defmodule Hawk.OpenApi do
  @moduledoc """
  Composes OpenAPI specifications from Hawk JSON:API resource declarations.
  """

  def spec(resources, opts \\ []) when is_list(resources) do
    resources = Enum.map(resources, &normalize_resource/1)

    %{
      openapi: "3.1.0",
      info: %{
        title: Keyword.get(opts, :title, "Hawk API"),
        version: Keyword.get(opts, :version, "1.0.0")
      },
      servers: Keyword.get(opts, :servers, [%{url: "/"}]),
      security: Keyword.get(opts, :security, []),
      tags: tags(resources),
      paths: paths(resources, Keyword.get(opts, :path_prefix, "")),
      components: %{
        schemas: schemas(resources)
      }
    }
  end

  defp normalize_resource(model) when is_atom(model) do
    %{model: model, resource: model.__hawk_resource__(), json_api: model.__hawk_json_api__()}
  end

  defp tags(resources) do
    resources
    |> Enum.map(& &1.json_api[:tag])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&%{name: &1})
  end

  defp paths(resources, path_prefix) do
    Enum.reduce(resources, %{}, fn resource, paths ->
      Map.merge(paths, resource_paths(resource, path_prefix))
    end)
  end

  defp resource_paths(resource, path_prefix) do
    path = Path.join(["/", path_prefix, resource.json_api.type])
    member_path = path <> "/{id}"

    %{
      path => %{
        get: index_operation(resource),
        post: write_operation(resource, :creatable, "Create #{resource_name(resource)}", 201)
      },
      member_path => %{
        get: show_operation(resource),
        patch:
          write_operation(resource, :updatable, "Update #{resource_name(resource)}", 200,
            parameters: [id_parameter()]
          ),
        delete: delete_operation(resource)
      }
    }
    |> Map.merge(action_paths(resource, member_path))
  end

  defp index_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      summary: "List #{resource.json_api.type}",
      parameters: index_parameters(resource),
      responses: responses(resource, 200, array_schema(resource))
    })
  end

  defp show_operation(resource) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      summary: "Show #{resource_name(resource)}",
      parameters: [id_parameter()],
      responses: responses(resource, 200, data_schema(resource))
    })
  end

  defp write_operation(resource, capability, summary, success_status, opts \\ []) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
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
      summary: "Delete #{resource_name(resource)}",
      parameters: [id_parameter()],
      responses: responses(resource, 200, data_schema(resource))
    })
  end

  defp action_paths(resource, member_path) do
    resource.resource
    |> Hawk.Actions.actions()
    |> Enum.map(fn {name, metadata} ->
      {member_path <> "/-actions/" <> name, %{post: action_operation(resource, name, metadata)}}
    end)
    |> Map.new()
  end

  defp action_operation(resource, name, metadata) do
    resource
    |> operation_metadata()
    |> Map.merge(%{
      summary: "Run #{name} for #{resource_name(resource)}",
      description: metadata[:doc],
      parameters: [id_parameter()],
      requestBody: action_request_body(metadata),
      responses: responses(resource, 200, data_schema(resource))
    })
  end

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

  defp id_parameter do
    %{name: "id", in: "path", required: true, schema: %{type: "string"}}
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

  defp responses(_resource, success_status, success_schema) do
    %{
      Integer.to_string(success_status) =>
        json_api_content(success_description(success_status), success_schema),
      "400" => json_api_content("Invalid JSON:API query parameters", error_document_schema()),
      "403" => json_api_content("Forbidden by Hawk policy", error_document_schema()),
      "404" => json_api_content("Resource not found", error_document_schema()),
      "422" => json_api_content("Validation failed", error_document_schema())
    }
  end

  defp success_description(200), do: "JSON:API response"
  defp success_description(201), do: "JSON:API resource created"

  defp json_api_content(description, schema) do
    %{description: description, content: %{"application/vnd.api+json" => %{schema: schema}}}
  end

  defp data_schema(resource), do: %{type: "object", properties: %{data: schema_ref(resource)}}

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
      {name, field_schema(resource.model.__schema__(:type, name), metadata)}
    end)
  end

  defp relationship_properties(resource) do
    Map.new(resource.json_api.relationships, fn {name, metadata} ->
      {name, relationship_schema(metadata)}
    end)
  end

  defp writable_attributes(resource, capability) do
    allowed = Map.fetch!(resource.json_api, capability)

    resource.json_api.attributes
    |> Map.take(allowed)
    |> Map.new(fn {name, metadata} ->
      {name, field_schema(resource.model.__schema__(:type, name), metadata)}
    end)
  end

  defp writable_relationships(resource, capability) do
    allowed = Map.fetch!(resource.json_api, capability)

    resource.json_api.relationships
    |> Map.take(allowed)
    |> Map.new(fn {name, metadata} -> {name, relationship_schema(metadata)} end)
  end

  defp relationship_schema(metadata) do
    field_schema(:map, metadata)
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
    |> Enum.sort()
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
end

defmodule Hawk.OpenApi.Components do
  @moduledoc false

  @responses %{
    "400" => :BadRequest,
    "401" => :Unauthorized,
    "403" => :Forbidden,
    "404" => :NotFound,
    "406" => :NotAcceptable,
    "415" => :UnsupportedMediaType,
    "422" => :ValidationFailed
  }

  # Extract only generated operations. Application-owned extra paths are merged
  # afterwards; their parameters and error representations belong to the host.
  def extract(spec) do
    {paths, components} =
      Enum.map_reduce(spec.paths, spec.components, fn {path, operations}, components ->
        {operations, components} =
          Enum.map_reduce(operations, components, fn {method, operation}, components ->
            {responses, components} = extract_responses(operation.responses, components)
            {parameters, components} = extract_parameters(operation.parameters, components)
            {{method, %{operation | responses: responses, parameters: parameters}}, components}
          end)

        {{path, Map.new(operations)}, components}
      end)

    %{spec | paths: Map.new(paths), components: components}
  end

  defp extract_responses(responses, components) do
    {responses, components} =
      Enum.map_reduce(responses, components, fn {status, response}, components ->
        case Map.fetch(@responses, status) do
          {:ok, name} ->
            {ref, components} = register(components, :responses, name, response)
            {{status, ref}, components}

          :error ->
            {{status, response}, components}
        end
      end)

    {Map.new(responses), components}
  end

  defp extract_parameters(parameters, components) do
    Enum.map_reduce(parameters, components, fn parameter, components ->
      case parameter_name(parameter) do
        nil -> {parameter, components}
        name -> register(components, :parameters, name, parameter)
      end
    end)
  end

  defp parameter_name(%{name: "id", schema: %{format: "uuid"}}), do: :UuidId
  defp parameter_name(%{name: "id"}), do: :ReadId
  defp parameter_name(%{name: "include"}), do: :Include
  defp parameter_name(_parameter), do: nil

  defp register(components, kind, name, definition) do
    case get_in(components, [kind, name]) do
      nil ->
        components = Map.update(components, kind, %{name => definition}, &Map.put(&1, name, definition))
        {%{"$ref": "#/components/#{kind}/#{name}"}, components}

      ^definition ->
        {%{"$ref": "#/components/#{kind}/#{name}"}, components}

      _conflicting_definition ->
        raise ArgumentError, "conflicting OpenAPI component definitions for #{kind}/#{name}"
    end
  end
end

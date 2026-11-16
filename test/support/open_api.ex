defmodule Hawk.Test.OpenApi do
  @moduledoc false

  # Resolve only the reusable operation objects, retaining schema references so
  # existing schema assertions still verify the generated resource identities.
  def expand(spec), do: expand(spec, spec)

  defp expand(%{"$ref": "#/components/" <> path}, spec) do
    case String.split(path, "/") do
      [kind, name] when kind in ["parameters", "responses"] ->
        spec.components
        |> Map.fetch!(String.to_existing_atom(kind))
        |> Map.fetch!(String.to_existing_atom(name))
        |> expand(spec)

      _schema ->
        %{"$ref": "#/components/" <> path}
    end
  end

  defp expand(map, spec) when is_map(map), do: Map.new(map, fn {key, value} -> {key, expand(value, spec)} end)
  defp expand(list, spec) when is_list(list), do: Enum.map(list, &expand(&1, spec))
  defp expand(value, _spec), do: value
end

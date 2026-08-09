defmodule Hawk.Plans.Registry do
  @moduledoc """
  Maps JSON:API resource types to Hawk.Resource facades.

  Used by `Hawk.Plans` to resolve plan ops (which identify resources by
  JSON:API `type`) to the facades that execute them. Discovery scans compiled
  beams for `__hawk_resource__/1` — the same mechanism `mix hawk.validate` and
  `mix hawk.openapi` use.
  """

  @doc """
  Resolves a JSON:API `type` string to its Hawk.Resource facade module.

  Returns `{:ok, module}` or `:error`.
  """
  @spec resolve(String.t()) :: {:ok, module()} | :error
  def resolve(resource_type) when is_binary(resource_type) do
    case Map.get(registry(), resource_type) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  @doc """
  Returns the full type → facade map.
  """
  @spec registry() :: %{String.t() => module()}
  def registry do
    discovered_resources()
    |> Enum.sort()
    |> Enum.reduce(%{}, &maybe_register_resource/2)
  end

  defp maybe_register_resource(module, acc) do
    if hawk_resource?(module) and module.__hawk_resource__(:json_api) != false do
      register_resource(module, acc)
    else
      acc
    end
  end

  defp register_resource(module, acc) do
    type = Hawk.JsonApi.Schema.metadata(module.__hawk_resource__(:json_api)).type
    # First-discovered (alphabetically) wins, so a full resource
    # (Videdal.Courses) takes precedence over a test adapter
    # (Videdal.ExternalCourses) that reuses the same type.
    if Map.has_key?(acc, type), do: acc, else: Map.put(acc, type, module)
  end

  defp discovered_resources do
    # In Mix tasks (mix test, mix run), scan compiled beams. In IEx or a running
    # app, fall back to :code.all_loaded().
    beams = compiled_beams()

    if beams != [], do: beams, else: loaded_modules()
  end

  defp compiled_beams do
    path = Mix.Project.compile_path()

    path
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.map(fn beam -> beam |> Path.basename(".beam") |> String.to_atom() end)
    |> Enum.filter(&hawk_resource?/1)
  rescue
    _ -> []
  end

  defp loaded_modules do
    :code.all_loaded()
    |> Enum.filter(fn {module, _file} -> hawk_resource?(module) end)
    |> Enum.map(fn {module, _file} -> module end)
  end

  defp hawk_resource?(module) do
    Code.ensure_loaded(module) == {:module, module} and
      function_exported?(module, :__hawk_resource__, 1)
  rescue
    _ -> false
  end
end

defmodule Mix.Tasks.Hawk.Validate do
  @shortdoc "Validates Hawk resource declarations and adapter contracts"

  @moduledoc """
  Validates Hawk resource facade declarations against their sibling modules
  and the underlying Ecto models.

  This is the authoritative, order-independent gate that complements the
  compile-time warnings emitted by `use Hawk.Resource`. Compile-time validation
  warns (instead of raising) when a sibling module is not available yet, so a
  facade can compile before its siblings during incremental edits or code
  generation. This task runs the *same* validation in `:strict` mode — missing
  siblings raise — plus `Hawk.ResourceContract.validate!/3` cross-checks.

  ## Usage

      mix hawk.validate                  # discover and validate all Hawk resources
      mix hawk.validate MyApp.Courses    # validate explicit resource(s)

  Discovery loads every compiled `.beam` on the project code path and selects
  modules that export `__hawk_resource__/1`, so it works without registration
  and survives app restarts.
  """

  use Mix.Task

  alias Hawk.Resource.Validation

  @impl true
  def run(args) do
    # Ensure the project is compiled so beam-based discovery sees current code.
    Mix.Task.run("compile", [])

    resources =
      case parse_args(args) do
        [] -> discover_resources()
        explicit -> explicit
      end

    report(resources)
  end

  defp report([]) do
    Mix.shell().error("No Hawk resources found to validate.")
    :ok
  end

  defp report(resources) do
    errors = Enum.flat_map(resources, &validate_resource/1)

    case errors do
      [] ->
        Mix.shell().info("Hawk validation passed for #{length(resources)} resource(s).")
        :ok

      errors ->
        Mix.shell().error("\nHawk validation failed:\n")

        Enum.each(errors, fn {resource, message} ->
          Mix.shell().error("  * #{inspect(resource)}: #{message}")
        end)

        Mix.raise("Hawk validation failed with #{length(errors)} error(s)")
    end
  end

  defp parse_args(args) do
    Enum.map(args, fn arg ->
      arg
      |> String.split(".")
      |> Module.concat()
    end)
  end

  defp validate_resource(resource) do
    unless hawk_resource?(resource) do
      raise ArgumentError, "#{inspect(resource)} is not a Hawk.Resource facade (missing __hawk_resource__/1)"
    end

    modules = %{
      model: resource.__hawk_resource__(:model),
      reader: resource.__hawk_resource__(:reader),
      policy: resource.__hawk_resource__(:policy),
      writer: resource.__hawk_resource__(:writer),
      json_api: resource.__hawk_resource__(:json_api),
      live_view: resource.__hawk_resource__(:live_view),
      actions: resource.__hawk_resource__(:actions),
      identity: resource.__hawk_resource__(:identity)
    }

    Validation.validate!(modules, :strict)
    Hawk.ResourceContract.validate!(resource, modules.model)

    []
  rescue
    e in [ArgumentError, RuntimeError] ->
      [{resource, Exception.message(e)}]
  end

  defp discover_resources do
    compile_path = Mix.Project.compile_path()

    Path.wildcard(Path.join(compile_path, "*.beam"))
    |> Enum.reduce([], fn beam, acc ->
      module = beam |> Path.basename(".beam") |> String.to_atom()

      if hawk_resource?(module) do
        [module | acc]
      else
        acc
      end
    end)
    |> Enum.sort()
  end

  defp hawk_resource?(module) do
    Code.ensure_loaded(module) == {:module, module} and
      function_exported?(module, :__hawk_resource__, 1)
  rescue
    _ -> false
  end
end

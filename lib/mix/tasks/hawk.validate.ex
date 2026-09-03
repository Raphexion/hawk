defmodule Mix.Tasks.Hawk.Validate do
  @shortdoc "Validates Hawk resource declarations and adapter contracts"

  @moduledoc """
  Validates Hawk resource facade declarations and Hawk query declarations against
  their sibling modules and the underlying Ecto models.

  This is the authoritative, order-independent gate that complements the
  compile-time warnings emitted by `use Hawk.Resource`. Compile-time validation
  warns (instead of raising) when a sibling module is not available yet, so a
  facade can compile before its siblings during incremental edits or code
  generation. This task runs the *same* validation in `:strict` mode — missing
  siblings raise — plus `Hawk.ResourceContract.validate!/3` cross-checks.

  ## Usage

      mix hawk.validate                  # discover and validate all Hawk resources and queries
      mix hawk.validate MyApp.Courses    # validate explicit resource(s)
      mix hawk.validate MyApp.Query      # validate explicit query declarations

  Discovery loads every compiled `.beam` on the project code path and selects
  modules that export `__hawk_resource__/1` or `__hawk_query__/1`, so it works
  without registration and survives app restarts.
  """

  use Mix.Task

  alias Hawk.Query
  alias Hawk.Resource.Validation

  @impl true
  def run(args) do
    # Ensure the project is compiled so beam-based discovery sees current code.
    Mix.Task.run("compile", [])

    declarations =
      case parse_args(args) do
        [] -> discover_declarations()
        explicit -> explicit
      end

    report(declarations)
  end

  defp report([]) do
    Mix.shell().error("No Hawk declarations found to validate.")
    :ok
  end

  defp report(declarations) do
    errors = Enum.flat_map(declarations, &validate_declaration/1)

    case errors do
      [] ->
        resource_count = Enum.count(declarations, &hawk_resource?/1)
        query_count = Enum.count(declarations, &hawk_query?/1)

        Mix.shell().info("Hawk validation passed for #{resource_count} resource(s) and #{query_count} query(ies).")

        :ok

      errors ->
        Mix.shell().error("\nHawk validation failed:\n")

        Enum.each(errors, fn {declaration, message} ->
          Mix.shell().error("  * #{inspect(declaration)}: #{message}")
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

  defp validate_declaration(declaration) do
    cond do
      hawk_resource?(declaration) ->
        validate_resource(declaration)

      hawk_query?(declaration) ->
        validate_query(declaration)

      true ->
        raise ArgumentError,
              "#{inspect(declaration)} is not a Hawk.Resource facade or Hawk.Query declaration"
    end
  rescue
    e in [ArgumentError, RuntimeError] ->
      [{declaration, Exception.message(e)}]
  end

  defp validate_resource(resource) do
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
  end

  defp validate_query(query) do
    Query.validate!(query, :strict)
    []
  end

  defp discover_declarations do
    compile_path = Mix.Project.compile_path()

    Path.wildcard(Path.join(compile_path, "*.beam"))
    |> Enum.reduce([], fn beam, acc ->
      module = beam |> Path.basename(".beam") |> String.to_atom()

      if hawk_resource?(module) or hawk_query?(module) do
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

  defp hawk_query?(module) do
    Code.ensure_loaded(module) == {:module, module} and
      function_exported?(module, :__hawk_query__, 1)
  rescue
    _ -> false
  end
end

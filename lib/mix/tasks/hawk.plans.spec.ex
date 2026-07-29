defmodule Mix.Tasks.Hawk.Plans.Spec do
  @shortdoc "Generates a resource-shaped plan operation manifest from discovered Hawk resources"

  @moduledoc """
  Generates the plan operation manifest from every Hawk resource facade found
  on the project code path.

  This is the resource-shaped spec an external AI reads to compose plans — the
  second renderer over `Hawk.JsonApi.Routes` + `Hawk.Actions`, sitting alongside
  `mix hawk.openapi`. Where OpenAPI projects the resource surface to HTTP, this
  spec projects it to resource-shaped ops (`:read`, `:create`, `:update`,
  `:delete`, `:action`).

  ## Usage

      mix hawk.plans.spec -o tmp/plans.json
      mix hawk.plans.spec MyApp.Courses MyApp.Grades -o tmp/plans.json
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, resources, _invalid} =
      OptionParser.parse(args,
        strict: [output: :string],
        aliases: [o: :output]
      )

    Mix.Task.run("compile", [])

    output = Keyword.get(opts, :output) || raise ArgumentError, "mix hawk.plans.spec requires --output/-o"

    resources =
      case resources do
        [] -> discover_resources()
        explicit -> Enum.map(explicit, &parse_module/1)
      end

    spec = Hawk.Plans.Spec.spec(resources)

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode!(spec))

    Mix.shell().info("Wrote plan spec for #{length(resources)} resource(s) to #{output}")
  end

  defp parse_module(arg) do
    arg
    |> String.split(".")
    |> Module.concat()
  end

  defp discover_resources do
    Mix.Project.compile_path()
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Enum.reduce([], fn beam, acc ->
      module = beam |> Path.basename(".beam") |> String.to_atom()

      if hawk_resource?(module), do: [module | acc], else: acc
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

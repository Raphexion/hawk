defmodule Mix.Tasks.Hawk.Openapi do
  @shortdoc "Generates an OpenAPI spec from discovered Hawk resources"

  @moduledoc """
  Generates an OpenAPI specification from every Hawk resource facade found on
  the project code path.

  Discovery loads each compiled `.beam` and selects modules that export
  `__hawk_resource__/1`, so the spec stays in sync with the resources that
  actually exist — no hand-maintained list to drift. Resources with
  `json_api: false` are omitted by `Hawk.OpenApi.spec/2`.

  ## Usage

      mix hawk.openapi -o tmp/openapi.json
      mix hawk.openapi -o tmp/openapi.json --title "My API" --version 1.0.0 \\
        --path-prefix /api/v1

  Pass explicit resources to override discovery:

      mix hawk.openapi MyApp.Courses MyApp.Grades -o tmp/openapi.json
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, resources, _invalid} =
      OptionParser.parse(args,
        strict: [output: :string, title: :string, version: :string, path_prefix: :string],
        aliases: [o: :output]
      )

    Mix.Task.run("compile", [])

    output = Keyword.get(opts, :output) || raise ArgumentError, "mix hawk.openapi requires --output/-o"

    resources =
      case resources do
        [] -> discover_resources()
        explicit -> Enum.map(explicit, &parse_module/1)
      end

    spec =
      Hawk.OpenApi.spec(resources,
        title: Keyword.get(opts, :title, "Hawk API"),
        version: Keyword.get(opts, :version, "1.0.0"),
        path_prefix: Keyword.get(opts, :path_prefix, "")
      )

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode!(spec))

    Mix.shell().info("Wrote OpenAPI spec for #{length(resources)} resource(s) to #{output}")
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

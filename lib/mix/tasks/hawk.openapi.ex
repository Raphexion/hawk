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

  The `info.license` is the host application's choice — Hawk does not pick a
  license for you. Pass `--license` (and optionally `--license-url`) to render it:

      mix hawk.openapi -o tmp/openapi.json --license "Apache-2.0" \
        --license-url "https://www.apache.org/licenses/LICENSE-2.0"

  Pass explicit resources to override discovery:

      mix hawk.openapi MyApp.Courses MyApp.Grades -o tmp/openapi.json

  ## Options

    * `-o`/`--output` (required) — destination file.
    * `--title` (required) — info title. Hawk does not name the host app's API;
      the app must supply this.
    * `--version` — info version (default `"1.0.0"`).
    * `--path-prefix` — prefix applied to every path.
    * `--license` — license name for `info.license` (omitted when not set).
    * `--license-url` — optional license URL.
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, resources, _invalid} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          title: :string,
          version: :string,
          path_prefix: :string,
          license: :string,
          license_url: :string
        ],
        aliases: [o: :output]
      )

    Mix.Task.run("compile", [])

    output = Keyword.get(opts, :output) || raise ArgumentError, "mix hawk.openapi requires --output/-o"

    title = Keyword.get(opts, :title) || raise ArgumentError, "mix hawk.openapi requires --title — name the host app's API"

    resources =
      case resources do
        [] -> discover_resources()
        explicit -> Enum.map(explicit, &parse_module/1)
      end

    spec_opts =
      [
        title: title,
        version: Keyword.get(opts, :version, "1.0.0"),
        path_prefix: Keyword.get(opts, :path_prefix, "")
      ]
      |> put_license_opt(opts)

    spec = Hawk.OpenApi.spec(resources, spec_opts)

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode!(spec))

    Mix.shell().info("Wrote OpenAPI spec for #{length(resources)} resource(s) to #{output}")
  end

  defp parse_module(arg) do
    arg
    |> String.split(".")
    |> Module.concat()
  end

  # `--license` is the host app's choice; Hawk does not pick one. When supplied,
  # render `info.license` as `%{name: <license>, url: <license-url>}` (url optional).
  defp put_license_opt(spec_opts, opts) do
    case Keyword.get(opts, :license) do
      nil -> spec_opts
      name ->
        license = %{name: name} |> maybe_put_url(Keyword.get(opts, :license_url))
        Keyword.put(spec_opts, :license, license)
    end
  end

  defp maybe_put_url(license, nil), do: license
  defp maybe_put_url(license, url), do: Map.put(license, :url, url)

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

defmodule Mix.Tasks.Hawk.Gen.Resource do
  @shortdoc "Generates Hawk resource modules"

  @moduledoc """
  Generates the standard Hawk resource module set for an existing Ecto schema.

      mix hawk.gen.resource MyApp.Courses MyApp.Course --repo MyApp.Repo \
        --attributes title,code --relationships school,teacher

  By default the generated JSON:API fields are writable and a writer skeleton is
  emitted. Pass `--read-only` to generate `writer: false` and omit the writer.
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          attributes: :string,
          relationships: :string,
          filters: :string,
          preloads: :string,
          read_only: :boolean
        ],
        aliases: [r: :repo]
      )

    case positional do
      [resource, model] ->
        config = build_config(resource, model, opts)
        write_resource(config)
        write_policy(config)
        write_reader(config)
        write_json_api(config)
        write_live_view(config)
        maybe_write_writer(config)

      _other ->
        Mix.raise(
          "expected RESOURCE and MODEL, for example: mix hawk.gen.resource MyApp.Courses MyApp.Course --repo MyApp.Repo"
        )
    end
  end

  defp build_config(resource, model, opts) do
    repo = Keyword.get(opts, :repo) || Mix.raise("--repo is required")
    attributes = csv_atoms(Keyword.get(opts, :attributes, ""))
    relationships = csv_atoms(Keyword.get(opts, :relationships, ""))
    filters = [:id] ++ csv_atoms(Keyword.get(opts, :filters, ""))
    preloads = csv_atoms(Keyword.get(opts, :preloads, Enum.join(relationships, ",")))
    read_only? = Keyword.get(opts, :read_only, false)
    resource_name = resource |> module_parts() |> List.last() |> Macro.underscore()

    %{
      resource: resource,
      model: model,
      repo: repo,
      attributes: attributes,
      relationships: relationships,
      filters: Enum.uniq(filters),
      preloads: Enum.uniq(preloads),
      read_only?: read_only?,
      resource_name: resource_name,
      singular_name: singularize(resource_name),
      type: String.replace(resource_name, "_", "-"),
      base_path: module_path(resource)
    }
  end

  defp csv_atoms(""), do: []

  defp csv_atoms(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end

  defp module_path(module) do
    module
    |> module_parts()
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
  end

  defp module_parts(module), do: String.split(module, ".")

  defp singularize(name) do
    cond do
      String.ends_with?(name, "ies") -> String.replace_suffix(name, "ies", "y")
      String.ends_with?(name, "s") -> String.trim_trailing(name, "s")
      true -> name
    end
  end

  defp write_resource(config) do
    writer_line = if config.read_only?, do: ",\n    writer: false", else: ""

    write_ex("lib/#{config.base_path}.ex", """
    defmodule #{config.resource} do
      @moduledoc \"\"\"
      Hawk facade for #{config.type}.
      \"\"\"

      use Hawk.Resource,
        model: #{config.model}#{writer_line}
    end
    """)
  end

  defp write_policy(config) do
    write_ex("lib/#{config.base_path}/policy.ex", """
    defmodule #{config.resource}.Policy do
      @moduledoc \"\"\"
      Policy for #{config.type}.
      \"\"\"

      use Hawk.Policy

      read(:all)
      #{if config.read_only?, do: "write(:never)", else: "write(roles: [:admin])"}
    end
    """)
  end

  defp write_reader(config) do
    filters = Enum.map_join(config.filters, "\n", &"  filter(#{inspect(&1)})")
    sorts = Enum.map_join([:id | config.attributes], "\n", &"  sort(#{inspect(&1)})")
    preloads = Enum.map_join(config.preloads, "\n", &"  preload(#{inspect(&1)})")

    write_ex("lib/#{config.base_path}/reader.ex", """
    defmodule #{config.resource}.Reader do
      @moduledoc \"\"\"
      Reader for #{config.type}.
      \"\"\"

      use Hawk.Reader.Resource,
        repo: #{config.repo},
        schema: #{config.model}

    #{filters}
    #{sorts}
    #{preloads}
    end
    """)
  end

  defp write_json_api(config) do
    attributes = Enum.map_join(config.attributes, "\n", &json_api_attribute(&1, config))
    relationships = Enum.map_join(config.relationships, "\n", &json_api_relationship(&1, config))

    write_ex("lib/#{config.base_path}/json_api.ex", """
    defmodule #{config.resource}.JsonApi do
      @moduledoc \"\"\"
      JSON:API contract for #{config.type}.
      \"\"\"

      use Hawk.JsonApi.Resource

      type(#{inspect(config.type)})
      doc(#{inspect("#{Macro.camelize(config.resource_name)} resource.")})

    #{attributes}
    #{relationships}
    end
    """)
  end

  defp json_api_attribute(name, %{read_only?: true}), do: "  attribute(#{inspect(name)}, [])"
  defp json_api_attribute(name, _config), do: "  attribute(#{inspect(name)}, writable: true)"

  defp json_api_relationship(name, %{read_only?: true}),
    do: "  relationship(#{inspect(name)}, [])"

  defp json_api_relationship(name, _config) do
    "  relationship(#{inspect(name)}, writable: true)"
  end

  defp write_live_view(config) do
    filters =
      Enum.map_join(
        Enum.reject(config.filters, &(&1 == :id)),
        "\n",
        &"    filter(#{inspect(&1)})"
      )

    sorts = Enum.map_join(config.attributes, "\n", &"    sort(#{inspect(&1)})")
    columns = Enum.map_join(config.attributes, "\n", &"      column(#{inspect(&1)})")
    fields = Enum.map_join(config.attributes, "\n", &"    field(#{inspect(&1)})")

    write_ex("lib/#{config.base_path}/live_view.ex", """
    defmodule #{config.resource}.LiveView do
      @moduledoc \"\"\"
      LiveView contract for #{config.type}.
      \"\"\"

      use Hawk.LiveView.Resource

      as(#{inspect(String.to_atom(config.singular_name))})
      plural_as(#{inspect(String.to_atom(config.resource_name))})

      index do
    #{filters}
    #{sorts}

        table do
    #{columns}
        end
      end

      show do
    #{fields}
      end
    end
    """)
  end

  defp maybe_write_writer(%{read_only?: true}), do: :ok

  defp maybe_write_writer(config) do
    writer_fields =
      config.attributes ++ Enum.map(config.relationships, &relationship_foreign_key/1)

    cast_fields = inspect(writer_fields, charlists: :as_lists)

    write_ex("lib/#{config.base_path}/writer.ex", """
    defmodule #{config.resource}.Writer do
      @moduledoc \"\"\"
      Writer for #{config.type}.
      \"\"\"

      use Hawk.Writer.Resource,
        model: #{config.model},
        repo: #{config.repo},
        policy: #{config.resource}.Policy

      create do
        cast(#{cast_fields})
        validate_required(#{cast_fields})
      end

      update do
        cast(#{cast_fields})
      end

      def delete(%#{config.model}{} = model, authority) do
        model
        |> Hawk.MutationContext.delete(authority)
        |> Hawk.MutationContext.validate_policy(&#{config.resource}.Policy.delete?/1)
        |> Hawk.RepositoryBoundary.delete(#{config.repo})
      end
    end
    """)
  end

  defp relationship_foreign_key(name), do: String.to_atom("#{name}_id")

  defp write_ex(path, content) do
    formatted = content |> Code.format_string!() |> IO.iodata_to_binary()
    Mix.Generator.create_file(path, formatted)
  end
end

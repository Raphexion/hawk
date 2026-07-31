defmodule Mix.Tasks.Hawk.Gen.Resource do
  @shortdoc "Generates Hawk resource modules"

  @moduledoc """
  Generates the standard Hawk resource module set for an existing Ecto schema.

      mix hawk.gen.resource MyApp.Courses MyApp.Course --repo MyApp.Repo \
        --attributes title,code --relationships school,teacher

  By default the generated JSON:API fields are writable and a writer skeleton is
  emitted. Pass `--read-only` to gate writes with `write(:never)` in the policy;
  the writer skeleton is still emitted so routes exist and refuse writes.
  Pass `--web MyAppWeb` to also generate a Phoenix JSON:API controller,
  LiveView index/show modules and templates, and a router snippet.

  ## Options

    * `--repo` (required) — the `Ecto.Repo` module for reader/writer.
    * `--attributes` — comma-separated field names for JSON:API attributes.
    * `--relationships` — comma-separated association names for relationships.
    * `--filters` — comma-separated reader filter columns.
    * `--preloads` — comma-separated reader preload associations.
    * `--read-only` — gate writes with `write(:never)` (writer still emitted).
    * `--web` — the web module; also generate controller + LiveView + router.
    * `--public` — generate LiveViews using public authority access.
    * `--identity` — the identity field for view-backed resources.
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
          read_only: :boolean,
          web: :string,
          public: :boolean,
          identity: :string
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
        maybe_write_phoenix(config)

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
    identity = opts |> Keyword.get(:identity, "id") |> String.to_atom()
    filters = [identity] ++ csv_atoms(Keyword.get(opts, :filters, ""))
    preloads = csv_atoms(Keyword.get(opts, :preloads, Enum.join(relationships, ",")))
    read_only? = Keyword.get(opts, :read_only, false)
    web = Keyword.get(opts, :web)
    public? = Keyword.get(opts, :public, true)
    resource_name = resource |> module_parts() |> List.last() |> Macro.underscore()
    singular_name = singularize(resource_name)

    %{
      resource: resource,
      model: model,
      repo: repo,
      attributes: attributes,
      relationships: relationships,
      identity: identity,
      filters: Enum.uniq(filters),
      preloads: Enum.uniq(preloads),
      read_only?: read_only?,
      web: web,
      public?: public?,
      resource_name: resource_name,
      singular_name: singular_name,
      singular_module: Macro.camelize(singular_name),
      type: String.replace(resource_name, "_", "-"),
      base_path: module_path(resource),
      web_path: if(web, do: module_path(web))
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
    identity_opt =
      if config.identity == :id, do: "", else: ",\n    identity: #{inspect(config.identity)}"

    write_ex("lib/#{config.base_path}.ex", """
    defmodule #{config.resource} do
      @moduledoc false

      use Hawk.Resource,
        model: #{config.model}#{identity_opt}
    end
    """)
  end

  defp write_policy(config) do
    write_ex("lib/#{config.base_path}/policy.ex", """
    defmodule #{config.resource}.Policy do
      @moduledoc false

      use Hawk.Policy

      read(:all)
      #{if config.read_only?, do: "write(:never)", else: "write(roles: [:admin])"}
    end
    """)
  end

  defp write_reader(config) do
    filters = Enum.map_join(config.filters, "\n", &"  filter(#{inspect(&1)})")
    sorts = Enum.map_join([config.identity | config.attributes], "\n", &"  sort(#{inspect(&1)})")
    preloads = Enum.map_join(config.preloads, "\n", &"  preload(#{inspect(&1)})")

    write_ex("lib/#{config.base_path}/reader.ex", """
    defmodule #{config.resource}.Reader do
      @moduledoc false

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
      @moduledoc false

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

  defp json_api_relationship(name, _config),
    do: "  relationship(#{inspect(name)}, writable: true)"

  defp write_live_view(config) do
    filters =
      config.filters
      |> Enum.reject(&(&1 == :id))
      |> Enum.map_join("\n", &"    filter(#{inspect(&1)})")

    sorts = Enum.map_join(config.attributes, "\n", &"    sort(#{inspect(&1)})")
    columns = Enum.map_join(config.attributes, "\n", &"      column(#{inspect(&1)})")
    fields = Enum.map_join(config.attributes, "\n", &"    field(#{inspect(&1)})")

    write_ex("lib/#{config.base_path}/live_view.ex", """
    defmodule #{config.resource}.LiveView do
      @moduledoc false

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

  defp maybe_write_writer(config) do
    writer_fields =
      config.attributes ++ Enum.map(config.relationships, &relationship_foreign_key/1)

    cast_fields = inspect(writer_fields, charlists: :as_lists)

    write_ex("lib/#{config.base_path}/writer.ex", """
    defmodule #{config.resource}.Writer do
      @moduledoc false

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

      delete(:default)
    end
    """)
  end

  defp maybe_write_phoenix(%{web: nil}), do: :ok

  defp maybe_write_phoenix(config) do
    write_controller(config)
    write_live_index(config)
    write_live_show(config)
    write_router_snippet(config)
  end

  defp write_controller(config) do
    write_ex("lib/#{config.web_path}/controllers/api/#{config.singular_name}_controller.ex", """
    defmodule #{config.web}.Api.#{config.singular_module}Controller do
      @moduledoc false

      use #{config.web}, :controller

      use Hawk.JsonApi.Controller,
        resource: #{config.resource},
        public: #{inspect(config.public?)}
    end
    """)
  end

  defp write_live_index(config) do
    write_ex("lib/#{config.web_path}/live/#{config.singular_name}_live/index.ex", """
    defmodule #{config.web}.#{config.singular_module}Live.Index do
      @moduledoc false

      use #{config.web}, :live_view

      use Hawk.LiveView,
        resource: #{config.resource}

      @impl true
      def mount(_params, session, socket) do
        authority = Hawk.Authority.Session.authority_or_public(session)
        {:ok, assign_index(socket, authority)}
      end
    end
    """)

    write_heex(
      "lib/#{config.web_path}/live/#{config.singular_name}_live/index.html.heex",
      index_template(config)
    )
  end

  defp index_template(config) do
    columns = Enum.map_join([:id | config.attributes], "\n", &index_column/1)
    values = Enum.map_join(config.attributes, "\n", &index_value(&1, config))
    singular = config.singular_name

    """
    <Layouts.app flash={@flash}>
      <div class=\"space-y-6\">
        <div>
          <h1 class=\"text-3xl font-semibold tracking-tight\">#{Macro.camelize(config.resource_name)}</h1>
          <p class=\"mt-2 text-sm text-zinc-600\">Generated Hawk LiveView index.</p>
        </div>

        <div class=\"overflow-hidden rounded-2xl border border-zinc-200 bg-white shadow-sm\">
          <table class=\"w-full text-left text-sm\">
            <thead class=\"bg-zinc-50 text-zinc-600\">
              <tr>
    #{columns}
              </tr>
            </thead>
            <tbody class=\"divide-y divide-zinc-100\">
              <tr :for={#{singular} <- @#{config.resource_name}} id={\"#{singular}-__HASH__{#{singular}.id}\"} class=\"hover:bg-zinc-50\">
                <td class=\"px-4 py-3 font-medium\">
                  <.link navigate={~p\"/#{config.resource_name}/__HASH__{#{singular}.id}\"} class=\"text-blue-700 hover:underline\">
                    {#{singular}.id}
                  </.link>
                </td>
    #{values}
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
    |> String.replace("__HASH__", "#")
  end

  defp index_column(name),
    do: "            <th class=\"px-4 py-3 font-medium\">#{humanize(name)}</th>"

  defp index_value(name, config) do
    "            <td class=\"px-4 py-3\">{#{config.singular_name}.#{name}}</td>"
  end

  defp write_live_show(config) do
    write_ex("lib/#{config.web_path}/live/#{config.singular_name}_live/show.ex", """
    defmodule #{config.web}.#{config.singular_module}Live.Show do
      @moduledoc false

      use #{config.web}, :live_view

      use Hawk.LiveView,
        resource: #{config.resource}

      @impl true
      def mount(%{"id" => id}, session, socket) do
        authority = Hawk.Authority.Session.authority_or_public(session)
        {:ok, assign_show(socket, authority, id)}
      end
    end
    """)

    write_heex(
      "lib/#{config.web_path}/live/#{config.singular_name}_live/show.html.heex",
      show_template(config)
    )
  end

  defp show_template(config) do
    fields = Enum.map_join(config.attributes, "\n", &show_field(&1, config))

    """
    <Layouts.app flash={@flash}>
      <div :if={assigns[:hawk_error]} class=\"rounded-xl bg-red-50 p-4 text-red-800\">
        {Enum.map_join(@hawk_error.base, \", \")}
      </div>

      <div :if={assigns[:#{config.singular_name}]} class=\"space-y-6\">
        <.link navigate={~p\"/#{config.resource_name}\"} class=\"text-sm text-blue-700 hover:underline\">← Back to #{config.resource_name}</.link>

        <div>
          <p class=\"text-sm text-zinc-500\">#{Macro.camelize(config.singular_name)}</p>
          <h1 class=\"text-3xl font-semibold tracking-tight\">#{Macro.camelize(config.singular_name)} {@#{config.singular_name}.id}</h1>
        </div>

        <dl class=\"rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm\">
    #{fields}
        </dl>
      </div>
    </Layouts.app>
    """
  end

  defp show_field(name, config) do
    "      <div class=\"border-b border-zinc-100 py-3 last:border-0\"><dt class=\"text-sm text-zinc-500\">#{humanize(name)}</dt><dd class=\"mt-1 font-medium\">{@#{config.singular_name}.#{name}}</dd></div>"
  end

  defp write_router_snippet(config) do
    write_text("lib/#{config.web_path}/hawk_#{config.resource_name}_routes.exs", """
    # Add these routes to #{config.web}.Router:
    #
    # scope \"/\", #{config.web} do
    #   pipe_through :browser
    #   live \"/#{config.resource_name}\", #{config.singular_module}Live.Index, :index
    #   live \"/#{config.resource_name}/:id\", #{config.singular_module}Live.Show, :show
    # end
    #
    # scope \"/api\" do
    #   pipe_through :api
    #   import Hawk.JsonApi.Router
    #   hawk_json_api(#{config.resource}, #{config.web}.Api.#{config.singular_module}Controller)
    # end
    """)
  end

  defp relationship_foreign_key(name), do: String.to_atom("#{name}_id")

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp write_ex(path, content) do
    formatted = content |> Code.format_string!() |> IO.iodata_to_binary()
    Mix.Generator.create_file(path, formatted)
  end

  defp write_heex(path, content) do
    Mix.Generator.create_file(path, String.trim_leading(content))
  end

  defp write_text(path, content) do
    Mix.Generator.create_file(path, String.trim_leading(content))
  end
end

defmodule Hawk.Resource do
  @moduledoc """
  Resource facade: the single entry point that ties a Hawk resource together.

  A Hawk resource is a set of small sibling modules — a model, a reader, a
  policy, a writer, a JSON:API adapter, and (optionally) a LiveView adapter and
  an actions module — that describe one domain resource. `use Hawk.Resource`
  is the one-line declaration that resolves those siblings by convention,
  validates their contracts against each other at compile time, and generates
  the public facade a consumer calls: `one/1`, `all/1`, `create/2`, `update/3`,
  `delete/2`, action delegations, and `__hawk_resource__/1` introspection.

  This is the golden path. Everything else in Hawk exists to give this facade
  something to compose.

  ## The convention

  `use Hawk.Resource, model: MyApp.Course` expects sibling modules named after
  the facade module:

  | Sibling        | Module                  | Required | Disables with        |
  |----------------|-------------------------|----------|---------------------|
  | model          | (the `:model` opt)      | yes      | —                   |
  | reader         | `MyApp.Courses.Reader`  | yes      | —                   |
  | policy         | `MyApp.Courses.Policy`  | yes      | —                   |
  | writer         | `MyApp.Courses.Writer`  | yes      | `writer: false`     |
  | json_api        | `MyApp.Courses.JsonApi` | yes      | `json_api: false`    |
  | live_view       | `MyApp.Courses.LiveView`| yes      | `live_view: false`  |
  | actions        | `MyApp.Courses.Actions` | no       | (omitted by default) |

  Reader, policy, writer, JSON:API, and LiveView are *resolved by convention*
  — they cannot be passed as options (the `:policy` and `:writer` opts raise
  with a message pointing at the right fix). Actions is opt-in: it is only
  wired when an `Actions` sibling exists or is supplied explicitly.

  ## Compile-time phases

  `__using__/1` runs three phases:

    1. **Resolve** — discovers each sibling by convention or explicit option.
       A missing *required* sibling is a compile-time warning during
       incremental edits/codegen, and a hard error under `mix hawk.validate`
       (see `Hawk.Resource.Validation`).
    2. **Validate** — `Hawk.Resource.Validation.validate!/2` checks that every
       *present* sibling has the shape Hawk needs: required functions exist,
       and adapter contracts (JSON:API attributes/relationships, reader
       filters/sorts/preloads, policy scopes) agree with the model and each
       other. Present-but-malformed siblings always raise; that is real
       contract drift, not a write-order artifact.
    3. **Generate** — emits `__hawk_resource__/1` and the reader/writer/action
       delegations.

  ## Options

    * `:model` (required) — the `Hawk.Model` (or plain `Ecto.Schema`) backing
      the resource.
    * `:identity` — the field used as the JSON:API `id` and member-lookup key
      (default `:id`). Declare a non-`id` identity for view-backed projections;
      see "ID-less and view-backed resources" in the README.
    * `:writer` — `false` to disable the writer (read-only resource).
    * `:json_api` — `false` to disable the JSON:API adapter.
    * `:live_view` — `false` to disable the LiveView adapter.
    * `:actions` — an explicit actions module, or `false`.

  ## Examples

  The one-line resource:

      defmodule MyApp.Courses do
        use Hawk.Resource, model: MyApp.Course
      end

  A read-only resource with no JSON:API surface:

      defmodule MyApp.CourseSummaries do
        use Hawk.Resource,
          model: MyApp.CourseSummary,
          writer: false,
          json_api: false,
          live_view: false
      end

  A view-backed projection with a declared identity:

      defmodule MyApp.CourseGradeSummaries do
        use Hawk.Resource,
          model: MyApp.CourseGradeSummary,
          identity: :course_id
      end

  ## Introspection

  Every facade exposes `__hawk_resource__/1`, which returns the resolved
  sibling module (or `false`) for `:model`, `:reader`, `:policy`, `:writer`,
  `:json_api`, `:live_view`, `:actions`, the declared `:identity`, and a
  `:capabilities` map of booleans. `mix hawk.validate`, `mix hawk.openapi`,
  and `Hawk.Plans.Registry` all discover resources by scanning for this
  function.

  ## See also

    * `Hawk.Model` — the schema DSL and association resource metadata.
    * `Hawk.Reader.Resource` — the reader DSL (filters, sorts, preloads).
    * `Hawk.Writer.Resource` — the writer DSL (create/update/delete).
    * `Hawk.Policy` — the read/write policy DSL.
    * `Hawk.Actions` — custom `/-actions/` DSL.
    * `Hawk.JsonApi.Resource` / `Hawk.LiveView.Resource` — the adapters.
    * `Hawk.Resource.Validation` — the compile-time and `mix hawk.validate`
      contract gate.
  """

  alias Hawk.Resource.Validation

  @doc """
  Invokes the resource facade DSL.

  See the module documentation for the full option reference, the sibling
  convention, and the compile-time phases. This macro is not called directly;
  it runs at `use Hawk.Resource, ...`.
  """
  defmacro __using__(opts) do
    caller = __CALLER__.module
    model = Keyword.fetch!(opts, :model)

    env = __CALLER__

    if Keyword.has_key?(opts, :policy) do
      raise ArgumentError,
            "Hawk resources resolve policy by convention as #{inspect(Module.concat(caller, Policy))}; " <>
              "the :policy opt is not accepted"
    end

    if Keyword.has_key?(opts, :writer) do
      raise ArgumentError,
            "Hawk resources resolve writer by convention as #{inspect(Module.concat(caller, Writer))}; " <>
              "gate writes with the policy instead (the :writer opt is not accepted)"
    end

    identity = Keyword.get(opts, :identity, :id)

    unless is_atom(identity) do
      raise ArgumentError,
            "Hawk resource :identity must be an atom naming the field used as the " <>
              "JSON:API id and member lookup key (default :id); got: #{inspect(identity)}"
    end

    modules = %{
      model: Macro.expand(model, env),
      reader: resolve_module(caller, opts, :reader, Reader, env, required?: true),
      policy: Module.concat(caller, Policy),
      writer: Module.concat(caller, Writer),
      json_api: resolve_module(caller, opts, :json_api, JsonApi, env, required?: true),
      live_view: resolve_module(caller, opts, :live_view, LiveView, env, required?: true),
      actions: resolve_module(caller, opts, :actions, Actions, env, required?: false),
      identity: identity
    }

    Validation.validate!(modules, :compile)

    quote do
      unquote(quote_introspection(modules))
      unquote(quote_reader_delegates(modules.reader))
      unquote(quote_writer_delegates(modules.writer))
      unquote(quote_action_delegates(caller, modules.actions))
    end
  end

  defp resolve_module(caller, opts, key, suffix, env, required?: required?) do
    case Keyword.fetch(opts, key) do
      {:ok, false} ->
        false

      {:ok, module} ->
        Macro.expand(module, env)

      :error ->
        module = Module.concat(caller, suffix)

        if required? or compiled?(module) do
          module
        else
          false
        end
    end
  end

  defp compiled?(module), do: match?({:module, ^module}, Code.ensure_compiled(module))

  defp quote_introspection(modules) do
    capabilities = %{
      reader: modules.reader != false,
      writer: modules.writer != false,
      json_api: modules.json_api != false,
      live_view: modules.live_view != false,
      actions: modules.actions != false
    }

    entries = [
      {:model, modules.model},
      {:reader, modules.reader},
      {:policy, modules.policy},
      {:writer, modules.writer},
      {:json_api, modules.json_api},
      {:live_view, modules.live_view},
      {:actions, modules.actions},
      {:identity, modules.identity},
      {:capabilities, Macro.escape(capabilities)}
    ]

    clauses =
      Enum.map(entries, fn {key, value} ->
        quote do
          def __hawk_resource__(unquote(key)), do: unquote(value)
        end
      end)

    quote do
      (unquote_splicing(clauses))
    end
  end

  defp quote_reader_delegates(reader) do
    quote do
      def one(opts), do: unquote(reader).one(opts)
      def all(opts), do: unquote(reader).all(opts)
    end
  end

  defp quote_writer_delegates(writer) do
    form_delegates = quote_writer_form_delegates(writer)

    quote do
      def create(attrs, authority), do: unquote(writer).create(attrs, authority)
      def update(model, attrs, authority), do: unquote(writer).update(model, attrs, authority)
      def delete(model, authority), do: unquote(writer).delete(model, authority)
      unquote(form_delegates)
    end
  end

  defp quote_writer_form_delegates(writer) do
    if function_exported?(writer, :change_create, 2) and
         function_exported?(writer, :change_update, 3) do
      quote do
        def change_create(attrs, authority), do: unquote(writer).change_create(attrs, authority)

        def change_update(model, attrs, authority),
          do: unquote(writer).change_update(model, attrs, authority)
      end
    else
      []
    end
  end

  defp quote_action_delegates(_resource, false), do: []

  defp quote_action_delegates(_resource, actions_module) do
    actions = actions_module.__hawk_actions__()
    direct_delegates = Enum.map(actions, &quote_action_delegate(actions_module, &1))

    quote do
      unquote_splicing(direct_delegates)

      def action(name, model, params, authority) when is_binary(name) do
        with {:ok, metadata} <- Map.fetch(unquote(Macro.escape(actions)), name),
             true <- function_exported?(unquote(actions_module), metadata.handler, 3) do
          apply(unquote(actions_module), metadata.handler, [model, params, authority])
        else
          _other -> :unknown_action
        end
      end
    end
  end

  defp quote_action_delegate(actions_module, {_name, metadata}) do
    handler = metadata.handler

    quote do
      def unquote(handler)(model, params, authority) do
        unquote(actions_module).unquote(handler)(model, params, authority)
      end
    end
  end
end

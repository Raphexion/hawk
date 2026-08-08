defmodule Hawk.Resource do
  @moduledoc """
  Resource facade: the single entry point that ties a Hawk resource together.

  A Hawk resource is a set of small sibling modules — a model, a reader, a
  policy, a writer, a JSON:API adapter, and (optionally) a LiveView adapter and
  an actions module — that describe one domain resource. `use Hawk.Resource`
  is the one-line declaration that resolves those siblings by convention,
  validates their contracts against each other at compile time, and generates
  the public facade a consumer calls: `one/1`, `all/1`, `create/2`, `update/3`,
  `delete/2`, `action/4`, and `__hawk_resource__/1` introspection.

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
  | writer         | `MyApp.Courses.Writer`  | yes      | —                   |
  | json_api        | `MyApp.Courses.JsonApi` | yes      | `json_api: false`    |
  | live_view       | `MyApp.Courses.LiveView`| yes      | `live_view: false`  |
  | actions        | `MyApp.Courses.Actions` | no       | (omitted by default) |

  Reader, policy, and writer are *resolved by convention* — they are required
  siblings and cannot be passed as options (the `:policy` and `:writer` opts
  raise with a message pointing at the right fix). Writes are gated by the
  policy, not by omitting the writer: a read-only resource keeps its writer
  sibling and declares `write(:never)` in the policy. JSON:API and LiveView are
  optional adapters (`json_api: false` / `live_view: false`). `action/4` is
  always present and resolves the `Actions` sibling at runtime, returning
  `:unknown_action` when no action module or action exists.

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
    3. **Generate** — emits `__hawk_resource__/1`, reader/writer delegates,
       form-helper delegates, and runtime action dispatch.

  ## Options

    * `:model` (required) — the `Hawk.Model` (or plain `Ecto.Schema`) backing
      the resource.
    * `:identity` — the field used as the JSON:API `id` and member-lookup key
      (default `:id`). Declare a non-`id` identity for view-backed projections;
      see "ID-less and view-backed resources" in the README.
    * `:json_api` — `false` to disable the JSON:API adapter.
    * `:live_view` — `false` to disable the LiveView adapter.
    * `:actions` — an explicit actions module, or `false`.

  The writer is a required sibling and is always resolved by convention; gate
  writes with `write(:never)` in the policy instead of trying to omit it.

  ## Examples

  The one-line resource:

      defmodule MyApp.Courses do
        use Hawk.Resource, model: MyApp.Course
      end

  A read-only resource with no JSON:API surface (the writer sibling is still
  required; writes are refused by the policy):

      defmodule MyApp.CourseSummaries do
        use Hawk.Resource,
          model: MyApp.CourseSummary,
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
  sibling module for `:model`, `:reader`, `:policy`, `:writer`, `:actions`,
  and the declared `:identity`; `:json_api` and `:live_view` return the adapter
  module or `false` when disabled. The `:capabilities` map reports the
  optional adapter flags (`:json_api`, `:live_view`, `:actions`); the reader
  and writer are always present, so they have no capability flag. `mix
  hawk.validate`, `mix hawk.openapi`, and `Hawk.Plans.Registry` all discover
  resources by scanning for this function.

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

    runtime_modules = %{
      actions: runtime_module(caller, opts, :actions, Actions, env)
    }

    Validation.validate!(modules, :compile)

    quote do
      unquote(quote_introspection(modules, runtime_modules))
      unquote(quote_reader_delegates(modules.reader))
      unquote(quote_writer_delegates(modules.writer))
      unquote(quote_action_dispatch(caller))
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

  defp runtime_module(caller, opts, key, suffix, env) do
    case Keyword.fetch(opts, key) do
      {:ok, false} -> false
      {:ok, module} -> Macro.expand(module, env)
      :error -> Module.concat(caller, suffix)
    end
  end

  defp compiled?(module), do: match?({:module, ^module}, Code.ensure_compiled(module))

  @doc false
  def available_actions_module(false), do: false

  def available_actions_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__hawk_actions__, 0) do
      module
    else
      false
    end
  end

  @doc false
  def call_reader_count(reader, opts) when is_atom(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :count, 1) do
      reader.count(opts)
    else
      raise ArgumentError,
            "Hawk resource reader module #{inspect(reader)} must define count/1 " <>
              "to serve page[total]=true"
    end
  end

  @doc false
  def call_writer_change(writer, function, args) when is_atom(writer) and is_atom(function) and is_list(args) do
    arity = length(args)

    if Code.ensure_loaded?(writer) and function_exported?(writer, function, arity) do
      apply(writer, function, args)
    else
      raise ArgumentError,
            "Hawk resource writer module #{inspect(writer)} must define #{function}/#{arity} " <>
              "to use generated form helpers"
    end
  end

  @doc false
  def capabilities(static_capabilities, actions_module) when is_map(static_capabilities) do
    Map.put(static_capabilities, :actions, actions_module != false)
  end

  defp quote_introspection(modules, runtime_modules) do
    clauses =
      static_introspection_clauses(modules) ++
        [
          quote_actions_introspection(runtime_modules.actions),
          quote_capabilities_introspection(modules)
        ]

    quote do
      (unquote_splicing(clauses))
    end
  end

  defp static_introspection_clauses(modules) do
    [
      model: modules.model,
      reader: modules.reader,
      policy: modules.policy,
      writer: modules.writer,
      json_api: modules.json_api,
      live_view: modules.live_view,
      identity: modules.identity
    ]
    |> Enum.map(&quote_introspection_clause/1)
  end

  defp quote_introspection_clause({key, value}) do
    quote do
      def __hawk_resource__(unquote(key)), do: unquote(value)
    end
  end

  defp quote_actions_introspection(actions_module) do
    quote do
      def __hawk_resource__(:actions), do: Hawk.Resource.available_actions_module(unquote(actions_module))
    end
  end

  defp quote_capabilities_introspection(modules) do
    static_capabilities = %{
      json_api: modules.json_api != false,
      live_view: modules.live_view != false
    }

    quote do
      def __hawk_resource__(:capabilities),
        do: Hawk.Resource.capabilities(unquote(Macro.escape(static_capabilities)), __hawk_resource__(:actions))
    end
  end

  defp quote_reader_delegates(reader) do
    quote do
      def one(opts), do: unquote(reader).one(opts)
      def all(opts), do: unquote(reader).all(opts)
      def count(opts), do: Hawk.Resource.call_reader_count(unquote(reader), opts)
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
    quote do
      def change_create(attrs, authority),
        do: Hawk.Resource.call_writer_change(unquote(writer), :change_create, [attrs, authority])

      def change_update(model, attrs, authority),
        do: Hawk.Resource.call_writer_change(unquote(writer), :change_update, [model, attrs, authority])
    end
  end

  defp quote_action_dispatch(resource) do
    quote do
      def action(name, model, params, authority) when is_binary(name) do
        Hawk.Actions.dispatch(unquote(resource), name, model, params, authority)
      end
    end
  end
end

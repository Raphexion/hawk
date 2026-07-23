defmodule Hawk.Resource do
  @moduledoc """
  Resource facade DSL tying Hawk resource parts together.

  `use Hawk.Resource, model: MyApp.Course` follows the conventional sibling
  module layout and generates the public resource facade. Conventional modules
  are expected unless explicitly disabled with `false`.

  `__using__/1` runs three distinct phases:

    1. **Resolve** — discovers the sibling modules (Reader, Policy, Writer,
       JsonApi, LiveView, Actions) by convention or explicit option.
    2. **Validate** — delegates to `Hawk.Resource.Validation.validate!/1`, which
       fails fast when a module is missing, a required function is absent, or
       an adapter contract disagrees with the model or reader.
    3. **Generate** — emits the facade: `__hawk_resource__/1` introspection and
       reader/writer/action delegations.
  """

  alias Hawk.Resource.Validation

  defmacro __using__(opts) do
    caller = __CALLER__.module
    model = Keyword.fetch!(opts, :model)

    env = __CALLER__

    modules = %{
      model: Macro.expand(model, env),
      reader: resolve_module(caller, opts, :reader, Reader, env, required?: true),
      policy: resolve_module(caller, opts, :policy, Policy, env, required?: true),
      writer: resolve_module(caller, opts, :writer, Writer, env, required?: true),
      json_api: resolve_module(caller, opts, :json_api, JsonApi, env, required?: true),
      live_view: resolve_module(caller, opts, :live_view, LiveView, env, required?: true),
      actions: resolve_module(caller, opts, :actions, Actions, env, required?: false)
    }

    Validation.validate!(modules)

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

    quote do
      def __hawk_resource__(:model), do: unquote(modules.model)
      def __hawk_resource__(:reader), do: unquote(modules.reader)
      def __hawk_resource__(:policy), do: unquote(modules.policy)
      def __hawk_resource__(:writer), do: unquote(modules.writer)
      def __hawk_resource__(:json_api), do: unquote(modules.json_api)
      def __hawk_resource__(:live_view), do: unquote(modules.live_view)
      def __hawk_resource__(:actions), do: unquote(modules.actions)
      def __hawk_resource__(:capabilities), do: unquote(Macro.escape(capabilities))
    end
  end

  defp quote_reader_delegates(reader) do
    quote do
      def one(opts), do: unquote(reader).one(opts)
      def all(opts), do: unquote(reader).all(opts)
    end
  end

  defp quote_writer_delegates(false), do: []

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

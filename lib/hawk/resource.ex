defmodule Hawk.Resource do
  @moduledoc """
  Resource facade DSL tying Hawk resource parts together.

  `use Hawk.Resource, model: MyApp.Course` follows the conventional sibling
  module layout and generates the public resource facade. Conventional modules
  are expected unless explicitly disabled with `false`.
  """

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

    validate_modules!(modules)

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

  defp validate_modules!(modules) do
    validate_module!(modules.model, :model)
    validate_module!(modules.reader, :reader)
    validate_module!(modules.policy, :policy)
    validate_module!(modules.writer, :writer)
    validate_module!(modules.json_api, :json_api)
    validate_module!(modules.live_view, :live_view)
    validate_module!(modules.actions, :actions)

    validate_functions!(modules.reader, :reader, all: 1, one: 1, one!: 1)
    validate_functions!(modules.policy, :policy, read_filter: 1)
    validate_functions!(modules.writer, :writer, create: 2, update: 3, delete: 2)
    validate_functions!(modules.json_api, :json_api, __hawk_json_api__: 0)
    validate_functions!(modules.live_view, :live_view, __hawk_live_view__: 0)
    validate_functions!(modules.actions, :actions, __hawk_actions__: 0)

    validate_json_api_contract!(modules.model, modules.json_api)
  end

  defp validate_module!(false, _key), do: :ok

  defp validate_module!(module, key) when is_atom(module) do
    unless compiled?(module) do
      raise ArgumentError, "Hawk resource #{key} module #{inspect(module)} is not available"
    end
  end

  defp compiled?(module), do: match?({:module, ^module}, Code.ensure_compiled(module))

  defp validate_functions!(false, _key, _functions), do: :ok

  defp validate_functions!(module, key, functions) do
    Enum.each(functions, fn {function, arity} ->
      unless function_exported?(module, function, arity) do
        raise ArgumentError,
              "Hawk resource #{key} module #{inspect(module)} must define #{function}/#{arity}"
      end
    end)
  end

  defp validate_json_api_contract!(_model, false), do: :ok

  defp validate_json_api_contract!(model, json_api_module) do
    json_api = json_api_module.__hawk_json_api__()

    Enum.each(Map.get(json_api, :attributes, %{}), fn {name, metadata} ->
      source = Map.get(metadata, :source, name)

      if is_nil(model.__schema__(:type, source)) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} attribute #{inspect(name)} source #{inspect(source)} must reference a field on #{inspect(model)}"
      end
    end)

    Enum.each(Map.get(json_api, :relationships, %{}), fn {name, metadata} ->
      source = Map.get(metadata, :source, name)

      if is_nil(model.__schema__(:association, source)) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} relationship #{inspect(name)} source #{inspect(source)} must reference an association on #{inspect(model)}"
      end
    end)

    validate_json_api_capability!(json_api_module, json_api, :creatable)
    validate_json_api_capability!(json_api_module, json_api, :updatable)
  end

  defp validate_json_api_capability!(json_api_module, json_api, capability) do
    declared =
      json_api
      |> Map.get(:attributes, %{})
      |> Map.keys()
      |> Kernel.++(Map.keys(Map.get(json_api, :relationships, %{})))
      |> MapSet.new()

    json_api
    |> Map.get(capability, [])
    |> Enum.each(fn name ->
      unless MapSet.member?(declared, name) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} #{capability} field #{inspect(name)} must be declared as an attribute or relationship"
      end
    end)
  end

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
      def one!(opts), do: unquote(reader).one!(opts)
      def all(opts), do: unquote(reader).all(opts)
    end
  end

  defp quote_writer_delegates(false), do: []

  defp quote_writer_delegates(writer) do
    quote do
      def create(attrs, authority), do: unquote(writer).create(attrs, authority)
      def update(model, attrs, authority), do: unquote(writer).update(model, attrs, authority)
      def delete(model, authority), do: unquote(writer).delete(model, authority)
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

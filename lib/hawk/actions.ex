defmodule Hawk.Actions do
  @moduledoc """
  Declares JSON:API custom actions exposed under `/-actions/`.

  Resource action modules live next to `Reader` and `Writer` modules and define
  metadata Hawk can use for controller dispatch and OpenAPI generation.
  """

  defmacro __using__(_opts) do
    quote do
      import Hawk.Actions, only: [action: 2]

      Module.register_attribute(__MODULE__, :hawk_actions, accumulate: true)
      @before_compile Hawk.Actions
    end
  end

  defmacro action(name, opts) when is_list(opts) do
    metadata = action_metadata(name, opts, __CALLER__)

    quote do
      @hawk_actions unquote(Macro.escape(metadata))
    end
  end

  defmacro __before_compile__(env) do
    actions =
      env.module
      |> Module.get_attribute(:hawk_actions)
      |> Enum.reverse()
      |> Map.new(fn metadata -> {metadata.name, metadata} end)

    quote do
      def __hawk_actions__, do: unquote(Macro.escape(actions))
    end
  end

  def dispatch(resource, action_name, model, params, authority)
      when is_atom(resource) and is_binary(action_name) and is_struct(model) do
    actions_module = Module.concat(resource, Actions)

    with true <- Code.ensure_loaded?(actions_module),
         {:ok, actions} <- fetch_actions(actions_module),
         {:ok, metadata} <- Map.fetch(actions, action_name),
         true <- function_exported?(actions_module, metadata.handler, 3) do
      apply(actions_module, metadata.handler, [model, atomize_params(params, metadata), authority])
    else
      false -> :unknown_action
      :error -> :unknown_action
    end
  end

  def dispatch(_resource, _action_name, _model, _params, _authority), do: :unknown_action

  def actions(resource) when is_atom(resource) do
    actions_module = Module.concat(resource, Actions)

    with true <- Code.ensure_loaded?(actions_module),
         {:ok, actions} <- fetch_actions(actions_module) do
      actions
    else
      _other -> %{}
    end
  end

  defp fetch_actions(module) do
    if function_exported?(module, :__hawk_actions__, 0) do
      {:ok, module.__hawk_actions__()}
    else
      :error
    end
  end

  defp atomize_params(params, metadata) when is_map(params) do
    allowed = metadata.params |> Map.keys() |> MapSet.new()

    Map.new(params, fn {key, value} -> {param_key(key), value} end)
    |> Map.take(MapSet.to_list(allowed))
  end

  defp atomize_params(_params, _metadata), do: %{}

  defp param_key(key) when is_atom(key), do: key
  defp param_key(key) when is_binary(key), do: String.to_atom(key)

  defp action_metadata(name, opts, caller) do
    name = literal!(name, caller)
    handler = opts |> Keyword.get(:handler, default_handler(name)) |> literal!(caller)
    doc = opts |> Keyword.get(:doc) |> maybe_literal(caller)
    params = opts |> Keyword.get(:params, []) |> params_metadata(caller)

    %{name: name, handler: handler, doc: doc, params: params}
  end

  defp params_metadata(params, caller) when is_list(params) do
    params
    |> Enum.map(fn {name, opts} -> {literal!(name, caller), param_metadata(opts, caller)} end)
    |> Map.new()
  end

  defp params_metadata(params, caller) when is_map(params) do
    params
    |> Enum.map(fn {name, opts} -> {literal!(name, caller), param_metadata(opts, caller)} end)
    |> Map.new()
  end

  defp param_metadata(opts, caller) when is_list(opts) do
    %{}
    |> put_if_present(:type, opts[:type], caller)
    |> put_if_present(:doc, opts[:doc], caller)
    |> put_if_present(:example, opts[:example], caller)
  end

  defp put_if_present(map, _key, nil, _caller), do: map
  defp put_if_present(map, key, value, caller), do: Map.put(map, key, literal!(value, caller))

  defp default_handler(name) do
    name
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp maybe_literal(nil, _caller), do: nil
  defp maybe_literal(value, caller), do: literal!(value, caller)

  defp literal!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end
end

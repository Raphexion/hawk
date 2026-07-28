defmodule Hawk.Actions do
  @moduledoc """
  The custom-actions DSL: domain operations exposed under `/-actions/`.

  When a resource needs an operation that is not plain CRUD — open registration,
  close enrollment, finalize grades — declare it as an action. Action modules
  live next to `Reader` and `Writer` as `<Resource>.Actions`, and define both
  metadata (for controller dispatch and OpenAPI generation) and the handler
  function that runs the operation.

  An action receives the loaded model, atomized params, and the authority, and
  returns a `Hawk.Result` (or value) the JSON:API controller renders. It runs
  under the same policy boundary as writes; actions are how you expose domain
  verbs without forcing them into the writer's create/update shape.

  ## Example

      defmodule MyApp.Courses.Actions do
        use Hawk.Actions

        action("open-registration",
          doc: "Open course registration and configure seats.",
          params: [
            seat_count: [type: :integer, doc: "Seats offered.", example: 2],
            waitlist_count: [type: :integer, doc: "Waitlist capacity.", example: 1]
          ]
        )

        def open_registration(course, params, authority) do
          # ... build and persist ...
        end
      end

  ## Options

    * `:doc` — human-readable description, surfaced in OpenAPI.
    * `:handler` — the function name implementing the action (default: the
      dash-to-underscore form of the name, e.g. `"open-registration"` →
      `open_registration/3`).
    * `:params` — a keyword list or map of `{name, opts}`. Each param takes
      `:type`, `:doc`, `:example`, used for OpenAPI generation and param
      atomization.

  ## Generated functions

    * `__hawk_actions__/0` — the action metadata map, used by `Hawk.Actions.dispatch/5`
      and OpenAPI generation.

  ## See also

    * `Hawk.Actions.dispatch/5` — runtime dispatch used by the JSON:API controller.
    * `Hawk.OpenApi` — renders actions as `POST /-actions/{name}` operations.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Hawk.Actions, only: [action: 2]

      Module.register_attribute(__MODULE__, :hawk_actions, accumulate: true)
      @before_compile Hawk.Actions
    end
  end

  @doc """
  Declares a custom action under `/-actions/{name}`.

  ## Options

    * `:doc` — description surfaced in OpenAPI.
    * `:handler` — the implementing function (default: the name's underscore form).
    * `:params` — `{name, opts}` entries; each opts map supports `:type`, `:doc`,
      `:example`.
  """
  defmacro action(name, opts) when is_list(opts) do
    metadata = action_metadata(name, opts, __CALLER__)

    quote do
      @hawk_actions unquote(Macro.escape(metadata))
    end
  end

  @doc false
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

  @doc """
  Dispatches an action by name to its handler on the resource's `Actions` module.

  Returns the handler's result, or `:unknown_action` when the action or handler
  is absent. Used by the generated JSON:API controller.
  """
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

  @doc """
  Returns the action metadata map for a resource (`%{}` when the resource has
  no `Actions` module).
  """
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
    allowed_by_name = Map.new(Map.keys(metadata.params), &{to_string(&1), &1})

    Enum.reduce(params, %{}, fn
      {key, value}, acc when is_atom(key) ->
        if Map.has_key?(metadata.params, key), do: Map.put(acc, key, value), else: acc

      {key, value}, acc when is_binary(key) ->
        case Map.fetch(allowed_by_name, key) do
          {:ok, param_key} -> Map.put(acc, param_key, value)
          :error -> acc
        end
    end)
  end

  defp atomize_params(_params, _metadata), do: %{}

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

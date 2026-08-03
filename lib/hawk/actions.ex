defmodule Hawk.Actions do
  @moduledoc """
  The custom-actions DSL: domain operations exposed under `/-actions/`.

  When a resource needs an operation that is not plain CRUD — open registration,
  close enrollment, finalize grades — declare it as an action. Action modules
  live next to `Reader` and `Writer` as `<Resource>.Actions`, and define both
  metadata (for controller dispatch and OpenAPI generation) and the handler
  function that runs the operation.

  `Actions` is an orchestration layer above `Reader` and `Writer`. An action
  receives the loaded model, atomized params, and the authority, and composes
  reads and writes through the resource reader and writer using that authority.
  It returns a `Hawk.Result` (or value) the JSON:API controller renders.

  There is no separate action-level policy. Action handlers are trusted
  application code: Hawk dispatches the handler and passes its authority, but
  cannot enforce what the handler does with them. The author is responsible for
  routing every protected read and write through the appropriate Reader or
  Writer while passing that authority through unchanged. Those layers apply
  `read_filter/1` and `create?/update?/delete?`; direct Repo calls and other side
  effects are outside Hawk's authorization guarantees. Actions are how you
  expose domain verbs without forcing them into the writer's create/update
  shape.

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
          # Action handlers are trusted application code. Keep protected reads
          # and writes behind their Reader/Writer boundaries, and pass the
          # caller's authority through unchanged.
          {:ok, course} = MyApp.Courses.one(authority: authority, filter: %{id: course.id})
          MyApp.Courses.Writer.open_registration(course, params, authority)
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
    resource = Hawk.Actions.resource_module(env.module)

    actions =
      env.module
      |> Module.get_attribute(:hawk_actions)
      |> Enum.reverse()
      |> Enum.map(&maybe_rebind_handler(env.module, &1))
      |> Map.new(fn metadata -> {metadata.name, metadata} end)

    # An Action opts into the two-phase form by declaring `build: true` (or
    # `build: :fn_name`) in `action/2`. The author writes a single
    # `build_<handler>/3` (or the named fn) that returns a `Hawk.Multi` of
    # facade-call steps. `Hawk.Actions` then generates `<handler>_change/3`
    # (validate without committing) and `<handler>_run/3` (commit) as projections
    # of that one build fn, so the two phases cannot drift, and rebinds the
    # action's `:handler` to `<handler>_run` so dispatch calls the commit. An
    # Action without `build:` stays run-only: the hand-written `<handler>/3` is
    # the commit path and there is no validate phase. Multiple actions per module
    # mix freely — each action carries its own build fn.
    generated =
      env.module
      |> Module.get_attribute(:hawk_actions)
      |> Enum.reverse()
      |> Enum.flat_map(&generate_change_run(env.module, resource, &1))

    quote do
      unquote_splicing(generated)
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
    actions_module = actions_module(resource)

    with module when is_atom(module) and module != false <- actions_module,
         {:ok, actions} <- fetch_actions(module),
         {:ok, metadata} <- Map.fetch(actions, action_name),
         true <- function_exported?(module, metadata.handler, 3) do
      apply(module, metadata.handler, [model, atomize_params(params, metadata), authority])
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
    with module when is_atom(module) and module != false <- actions_module(resource),
         {:ok, actions} <- fetch_actions(module) do
      actions
    else
      _other -> %{}
    end
  end

  @doc false
  def actions_module(resource) when is_atom(resource) do
    if Code.ensure_loaded?(resource) and function_exported?(resource, :__hawk_resource__, 1) do
      resource.__hawk_resource__(:actions)
    else
      Hawk.Resource.available_actions_module(Module.concat(resource, Actions))
    end
  end

  defp fetch_actions(module) do
    if function_exported?(module, :__hawk_actions__, 0) do
      {:ok, module.__hawk_actions__()}
    else
      :error
    end
  end

  @doc false
  def resource_module(actions_module) do
    actions_module
    |> Module.split()
    |> Enum.drop(-1)
    |> Module.concat()
  end

  defp maybe_rebind_handler(module, %{build: build} = metadata) when is_atom(build) and not is_nil(build) do
    if Module.defines?(module, {build, 3}) do
      run_fn = String.to_atom("#{metadata.handler}_run")

      metadata
      |> Map.put(:change_handler, metadata.handler)
      |> Map.put(:handler, run_fn)
    else
      raise ArgumentError,
            "Hawk action #{inspect(metadata.name)} declared `build: #{inspect(build)}` " <>
              "but #{inspect(module)} does not define #{build}/3"
    end
  end

  defp maybe_rebind_handler(_module, metadata), do: metadata

  defp generate_change_run(module, resource, %{build: build, handler: handler})
       when is_atom(build) and not is_nil(build) do
    if Module.defines?(module, {build, 3}) do
      change_fn = String.to_atom("#{handler}_change")
      run_fn = String.to_atom("#{handler}_run")

      [
        quote do
          @doc false
          def unquote(change_fn)(model, params, authority) do
            unquote(build)(model, params, authority)
            |> Hawk.Multi.to_changesets()
          end

          @doc false
          def unquote(run_fn)(model, params, authority) do
            unquote(build)(model, params, authority)
            |> Hawk.Multi.execute(unquote(resource).Reader.repo())
          end
        end
      ]
    else
      []
    end
  end

  defp generate_change_run(_module, _resource, _metadata), do: []

  @doc """
  Atomizes a raw params map against an action's declared `params:` schema,
  dropping keys the action does not declare.

  Used by `Hawk.Actions.dispatch/5` before applying the handler, and exposed
  so LiveView helpers can atomize the same way before calling a generated
  `<handler>_change/3`.
  """
  def atomize_params(params, metadata) when is_map(params) do
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

  def atomize_params(_params, _metadata), do: %{}

  defp action_metadata(name, opts, caller) do
    name = literal!(name, caller)
    handler = opts |> Keyword.get(:handler, default_handler(name)) |> literal!(caller)
    doc = opts |> Keyword.get(:doc) |> maybe_literal(caller)
    params = opts |> Keyword.get(:params, []) |> params_metadata(caller)
    build = build_fn(opts[:build], handler, caller)

    %{name: name, handler: handler, doc: doc, params: params, build: build}
  end

  defp build_fn(nil, _handler, _caller), do: nil

  defp build_fn(true, handler, _caller), do: String.to_atom("build_#{handler}")

  defp build_fn(fn_name, _handler, caller) when is_atom(fn_name), do: literal!(fn_name, caller)

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

defmodule Hawk.Multi do
  @moduledoc """
  A Hawk-native transactional composer that calls the resource facade boundary.

  `Hawk.Multi` steals the *shape* of `Ecto.Multi` (named steps, composable,
  inspectable, transactional, all-or-nothing with prior-step results threaded
  forward) without using `Ecto.Multi` directly. `Ecto.Multi`'s operations are
  raw `repo.insert/update/delete` that bypass `Hawk.RepositoryBoundary` and the
  `policy_validated?` gate — the Write Invariant. `Hawk.Multi`'s operations
  call the resource facade's `create/2`, `update/3`, `delete/2`, and
  `action/4`, which go through `MutationContext.validate_policy` +
  `RepositoryBoundary` the same way a JSON:API controller does. No parallel
  write path.

  ## Example

      multi =
        Hawk.Multi.new()
        |> Hawk.Multi.delete(:remove_enrollment, Videdal.Enrollments, enrollment, authority)
        |> Hawk.Multi.create(:add_enrollment, Videdal.Enrollments, %{student_id: sid, course_id: cid}, authority)
        |> Hawk.Multi.run(:log, fn results -> {:ok, results} end)

      Hawk.Multi.execute(multi, MyApp.Repo)

  On failure, the whole transaction rolls back.
  """

  defstruct steps: []

  @type step :: %{
          name: atom(),
          op: :create | :update | :delete | :action | :run,
          resource: module() | nil,
          model: struct() | nil,
          attrs: map() | nil,
          action: String.t() | nil,
          params: map() | nil,
          authority: Hawk.Authority.t() | nil,
          fun: (map() -> {:ok, term()} | {:error, term()}) | nil
        }

  @type t :: %__MODULE__{steps: [step()]}

  @doc """
  Creates an empty multi.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds a named create step.

  `resource` is a `Hawk.Resource` facade. On execution, calls
  `resource.create(attrs, authority)`, which goes through the writer pipeline
  and `RepositoryBoundary`.
  """
  @spec create(t(), atom(), module(), map(), Hawk.Authority.t()) :: t()
  def create(%__MODULE__{} = multi, name, resource, attrs, authority)
      when is_atom(name) and is_atom(resource) and is_map(attrs) do
    add_step(multi, %{
      name: name,
      op: :create,
      resource: resource,
      model: nil,
      attrs: attrs,
      action: nil,
      params: nil,
      authority: authority,
      fun: nil
    })
  end

  @doc """
  Adds a named update step.

  On execution, calls `resource.update(model, attrs, authority)`.
  """
  @spec update(t(), atom(), module(), struct(), map(), Hawk.Authority.t()) :: t()
  def update(%__MODULE__{} = multi, name, resource, model, attrs, authority)
      when is_atom(name) and is_atom(resource) and is_struct(model) and is_map(attrs) do
    add_step(multi, %{
      name: name,
      op: :update,
      resource: resource,
      model: model,
      attrs: attrs,
      action: nil,
      params: nil,
      authority: authority,
      fun: nil
    })
  end

  @doc """
  Adds a named delete step.

  On execution, calls `resource.delete(model, authority)`.
  """
  @spec delete(t(), atom(), module(), struct(), Hawk.Authority.t()) :: t()
  def delete(%__MODULE__{} = multi, name, resource, model, authority)
      when is_atom(name) and is_atom(resource) and is_struct(model) do
    add_step(multi, %{
      name: name,
      op: :delete,
      resource: resource,
      model: model,
      attrs: nil,
      action: nil,
      params: nil,
      authority: authority,
      fun: nil
    })
  end

  @doc """
  Adds a named action step.

  On execution, calls `resource.action(action_name, model, params, authority)`.
  """
  @spec action(t(), atom(), module(), struct(), String.t(), map(), Hawk.Authority.t()) :: t()
  def action(%__MODULE__{} = multi, name, resource, model, action_name, params, authority)
      when is_atom(name) and is_atom(resource) and is_struct(model) and is_binary(action_name) do
    add_step(multi, %{
      name: name,
      op: :action,
      resource: resource,
      model: model,
      attrs: nil,
      action: action_name,
      params: params,
      authority: authority,
      fun: nil
    })
  end

  @doc """
  Adds a named computed step.

  `fun` receives the results map of all prior steps and returns
  `{:ok, value}` (threaded forward under `name`) or `{:error, reason}` (halts
  the multi). This is the escape hatch for branching and computing args from
  prior results. It runs at execute time under the transaction, so a dry-run
  cannot fully predict its effects without executing it — the same semantics as
  `Ecto.Multi.run/3`.
  """
  @spec run(t(), atom(), (map() -> {:ok, term()} | {:error, term()})) :: t()
  def run(%__MODULE__{} = multi, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    add_step(multi, %{
      name: name,
      op: :run,
      resource: nil,
      model: nil,
      attrs: nil,
      action: nil,
      params: nil,
      authority: nil,
      fun: fun
    })
  end

  @doc """
  Adds a pre-built step to the multi. Used by `Hawk.Plans` to add steps
  built from plan ops; rarely called directly.
  """
  @spec add_step(t(), step()) :: t()
  def add_step(%__MODULE__{steps: steps} = multi, step) do
    %{multi | steps: steps ++ [step]}
  end

  @doc """
  Returns the steps without executing. Useful for inspection and dry-run
  rendering.
  """
  @spec to_list(t()) :: [step()]
  def to_list(%__MODULE__{steps: steps}), do: steps

  @doc """
  Executes all steps in a single repo transaction, threading prior results
  forward. All-or-nothing: any step failure halts and rolls back the whole
  transaction.

  Returns `{:ok, results_map}` on success, or
  `{:error, failed_step_name, error_value, prior_results}` on failure.
  """
  @spec execute(t(), module(), keyword()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def execute(%__MODULE__{} = multi, repo, _opts \\ []) when is_atom(repo) do
    repo.transaction(fn -> run_steps(multi.steps) end)
    |> unwrap_transaction_result()
  end

  defp run_steps(steps) do
    Enum.reduce_while(steps, {%{}, nil}, fn step, {results, _failed} ->
      case run_step(step, results) do
        {:ok, value} -> {:cont, {Map.put(results, step.name, value), nil}}
        {:error, reason} -> {:halt, {results, {step.name, reason}}}
      end
    end)
  end

  defp unwrap_transaction_result({:ok, {results, nil}}), do: {:ok, results}

  defp unwrap_transaction_result({:ok, {results, {failed_name, reason}}}),
    do: {:error, failed_name, reason, results}

  defp unwrap_transaction_result({:error, message}) when is_binary(message),
    do: {:error, :transaction, message, %{}}

  defp run_step(%{op: :create, resource: resource, attrs: attrs, authority: authority}, _results) do
    case resource.create(attrs, authority) do
      {:ok, model} -> {:ok, model}
      {:invalid, context} -> {:error, {:invalid, context}}
      {:not_authorized, context} -> {:error, {:not_authorized, context}}
      {:error, message} -> {:error, {:error, message}}
    end
  end

  defp run_step(%{op: :update, resource: resource, model: model, attrs: attrs, authority: authority}, _results) do
    case resource.update(model, attrs, authority) do
      {:ok, model} -> {:ok, model}
      {:invalid, context} -> {:error, {:invalid, context}}
      {:not_authorized, context} -> {:error, {:not_authorized, context}}
      {:error, message} -> {:error, {:error, message}}
    end
  end

  defp run_step(%{op: :delete, resource: resource, model: model, authority: authority}, _results) do
    case resource.delete(model, authority) do
      {:ok, model} -> {:ok, model}
      :ok -> {:ok, nil}
      {:invalid, context} -> {:error, {:invalid, context}}
      {:not_authorized, context} -> {:error, {:not_authorized, context}}
      {:error, message} -> {:error, {:error, message}}
    end
  end

  defp run_step(
         %{op: :action, resource: resource, model: model, action: action, params: params, authority: authority},
         _results
       ) do
    case resource.action(action, model, params, authority) do
      {:ok, model} -> {:ok, model}
      :ok -> {:ok, nil}
      :unknown_action -> {:error, :unknown_action}
      {:invalid, context} -> {:error, {:invalid, context}}
      {:not_authorized, context} -> {:error, {:not_authorized, context}}
      {:error, message} -> {:error, {:error, message}}
    end
  end

  defp run_step(%{op: :run, fun: fun}, results) do
    fun.(results)
  end
end

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

  On failure, the whole transaction rolls back. A Multi deliberately supports
  one Repo only: every resource step must use the Repo passed to `execute/3`.
  Execution raises before opening the transaction when a resource reader points
  at a different Repo. `run/3` callbacks are application-owned escape hatches;
  Hawk cannot inspect their side effects, so they must honor the same Repo
  prerequisite.
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
  Validates every declarable step without committing, returning a map of
  step name to non-persisting changeset.

  This is the validate phase of a multi: each `:create`/`:update` step is run
  through its resource facade's `change_create/2` / `change_update/3`, which
  build a changeset with `action: :validate` and run the writer pipeline
  (including the policy `create?/update?` check) without crossing the
  repository boundary. `:delete` steps have no changeset to validate and are
  omitted from the result; their policy gate runs at commit.

  A multi containing `:action` or `:run` steps cannot be validated without
  committing — those ops' effects depend on execution (see `run/3`'s dry-run
  caveat). `to_changesets/1` raises for such multis, so an Action built around
  them is run-only and must be validated by other means (e.g. validating the
  underlying writers' `change_*` directly).

  ## Example

      multi =
        Hawk.Multi.new()
        |> Hawk.Multi.create(:grade, MyApp.Grades, %{score: 7, student_id: sid}, authority)
        |> Hawk.Multi.update(:course, MyApp.Courses, course, %{graded_count: n}, authority)

      %{grade: grade_changeset, course: course_changeset} = Hawk.Multi.to_changesets(multi)

  """
  @spec to_changesets(t()) :: %{atom() => Ecto.Changeset.t()}
  def to_changesets(%__MODULE__{steps: steps}) do
    Enum.reduce(steps, %{}, fn step, acc ->
      case step.op do
        :create ->
          validate_form_contract!(step.resource, :change_create, 2, :create)
          changeset = step.resource.change_create(step.attrs, step.authority)
          Map.put(acc, step.name, changeset)

        :update ->
          validate_form_contract!(step.resource, :change_update, 3, :update)
          changeset = step.resource.change_update(step.model, step.attrs, step.authority)
          Map.put(acc, step.name, changeset)

        :delete ->
          acc

        op when op in [:action, :run] ->
          raise ArgumentError,
                "Hawk.Multi.to_changesets/1 cannot validate a #{inspect(op)} step " <>
                  "(#{inspect(step.name)}); a multi using :action or :run is run-only " <>
                  "and cannot be live-validated"
      end
    end)
  end

  defp validate_form_contract!(resource, function, arity, op) do
    unless function_exported?(resource, function, arity) do
      raise ArgumentError,
            "Hawk.Multi.to_changesets/1 cannot validate a #{inspect(op)} step for " <>
              "#{inspect(resource)}: the facade does not expose #{function}/#{arity}. " <>
              "A multi :create/:update step is only validatable when its writer is a " <>
              "Hawk.Writer.Resource (or otherwise defines #{function}/#{arity}); " <>
              "a resource with a hand-written writer that omits the form boundary " <>
              "is run-only in a multi."
    end
  end

  @doc """
  Executes all steps in a single repo transaction, threading prior results
  forward. All-or-nothing: any step failure halts and rolls back the whole
  transaction.

  Returns `{:ok, results_map}` on success, or
  `{:error, failed_step_name, error_value, prior_results}` on failure.

  Every resource step must be backed by `repo`; Hawk.Multi does not coordinate
  transactions across multiple Repos and raises before execution when they
  differ. Hawk cannot inspect `run/3` callback side effects, so application code
  must keep those on the same Repo.

  Writer PubSub events are flushed after the transaction owned by this function
  commits. A Multi containing PubSub writers raises when called inside an
  unmanaged caller transaction because Hawk cannot observe that outer commit.
  """
  @spec execute(t(), module(), keyword()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def execute(%__MODULE__{} = multi, repo, _opts \\ []) when is_atom(repo) do
    validate_single_repo!(multi, repo)
    outer_transaction? = function_exported?(repo, :in_transaction?, 0) and repo.in_transaction?()
    validate_broadcast_boundary!(multi, outer_transaction?)

    {transaction_result, broadcast_capture} =
      Hawk.RepositoryBoundary.capture_broadcasts(fn ->
        repo.transaction(fn -> execute_steps(multi.steps, repo) end)
      end)

    result = unwrap_transaction_result(transaction_result)
    finalize_broadcast_capture(result, broadcast_capture, outer_transaction?)
    result
  end

  defp validate_single_repo!(%__MODULE__{steps: steps}, repo) do
    Enum.each(steps, fn
      %{name: name, resource: resource} when is_atom(resource) and not is_nil(resource) ->
        resource_repo = resource_repo!(resource)

        unless resource_repo == repo do
          raise ArgumentError,
                "Hawk.Multi runs in a single transaction and requires every resource to use " <>
                  "#{inspect(repo)}; step #{inspect(name)} uses #{inspect(resource)}, whose reader " <>
                  "uses #{inspect(resource_repo)}"
        end

      _step ->
        :ok
    end)
  end

  defp resource_repo!(resource) do
    reader = resource.__hawk_resource__(:reader)

    if is_atom(reader) and not is_nil(reader) and Code.ensure_loaded?(reader) and
         function_exported?(reader, :repo, 0) do
      reader.repo()
    else
      raise ArgumentError,
            "Hawk.Multi resource #{inspect(resource)} must resolve a reader that exposes repo/0"
    end
  end

  defp validate_broadcast_boundary!(multi, true) do
    broadcasting? =
      Enum.any?(multi.steps, fn
        %{resource: resource} when is_atom(resource) and not is_nil(resource) ->
          Hawk.PubSub.config_for_resource(resource) != nil

        _step ->
          false
      end)

    if broadcasting? and not Hawk.RepositoryBoundary.capturing_broadcasts?() do
      raise ArgumentError,
            "Hawk.Multi with PubSub writers must own the outer transaction so events can be " <>
              "published after commit"
    end
  end

  defp validate_broadcast_boundary!(_multi, false), do: :ok

  defp finalize_broadcast_capture(
         {:ok, _results},
         {:nested, _checkpoint},
         _outer_transaction?
       ),
       do: :ok

  defp finalize_broadcast_capture({:ok, _results}, capture, false),
    do: Hawk.RepositoryBoundary.flush_broadcasts(capture)

  defp finalize_broadcast_capture(_result, capture, _outer_transaction?),
    do: Hawk.RepositoryBoundary.discard_broadcasts(capture)

  defp execute_steps(steps, repo) do
    case run_steps(steps) do
      {:ok, results} ->
        results

      {:error, failed_name, reason, prior_results} ->
        repo.rollback({failed_name, reason, prior_results})
    end
  end

  defp run_steps(steps) do
    Enum.reduce_while(steps, {:ok, %{}}, fn step, {:ok, results} ->
      case run_step(step, results) do
        {:ok, value} -> {:cont, {:ok, Map.put(results, step.name, value)}}
        {:error, reason} -> {:halt, {:error, step.name, reason, results}}
      end
    end)
  end

  defp unwrap_transaction_result({:ok, results}), do: {:ok, results}

  defp unwrap_transaction_result({:error, {failed_name, reason, results}}),
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

defmodule Hawk.Plans do
  @moduledoc """
  Executes and previews plans — batches of resource-shaped operations an AI
  authors and a human reviews before execution.

  Plans are a human-in-the-loop execution mode over the existing JSON:API/Action
  resource surface. Each plan op is a resource-shaped call (`:create`,
  `:update`, `:delete`, `:action`) that resolves to the resource facade and
  goes through the same `Policy` → `RepositoryBoundary` as a JSON:API
  controller. The whole batch runs in a single `Hawk.Multi` transaction,
  all-or-nothing, under the **reviewer's** authority. No AI in the loop at
  execution.

  `preview/2` executes in a transaction and rolls back, giving the human a
  dry-run effects preview with full fidelity (including repo-level constraints).
  `run/2` executes and commits.

  """

  alias Hawk.Authority
  alias Hawk.Multi
  alias Hawk.Plan

  @doc """
  Converts a plan into a `Hawk.Multi` by resolving each op to the resource
  facade and loading any referenced member records.

  Returns `{:ok, multi}` or `{:error, reason}`.
  """
  @spec to_multi(Plan.t(), Authority.t()) :: {:ok, Multi.t()} | {:error, term()}
  def to_multi(%Plan{ops: ops}, authority) do
    build_multi(ops, authority, Multi.new())
  end

  defp build_multi([], _authority, multi), do: {:ok, multi}

  defp build_multi([op | rest], authority, multi) do
    step_name = step_name(multi)

    case build_step(op, authority, step_name) do
      {:ok, multi_step} ->
        build_multi(rest, authority, Multi.add_step(multi, multi_step))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp step_name(%Multi{steps: steps}), do: String.to_atom("step_#{length(steps) + 1}")

  defp build_step(%{op: :create, resource: resource_type, attrs: attrs}, authority, name) do
    with {:ok, resource} <- resolve_resource(resource_type) do
      {:ok, step(name, :create, resource, nil, attrs, nil, nil, authority)}
    end
  end

  defp build_step(%{op: :update, resource: resource_type, id: id, attrs: attrs}, authority, name) do
    with {:ok, resource} <- resolve_resource(resource_type),
         {:ok, model} <- load_member(resource, id, authority) do
      {:ok, step(name, :update, resource, model, attrs, nil, nil, authority)}
    end
  end

  defp build_step(%{op: :delete, resource: resource_type, id: id}, authority, name) do
    with {:ok, resource} <- resolve_resource(resource_type),
         {:ok, model} <- load_member(resource, id, authority) do
      {:ok, step(name, :delete, resource, model, nil, nil, nil, authority)}
    end
  end

  defp build_step(
         %{op: :action, resource: resource_type, id: id, action: action, params: params},
         authority,
         name
       ) do
    with {:ok, resource} <- resolve_resource(resource_type),
         {:ok, model} <- load_member(resource, id, authority) do
      {:ok, step(name, :action, resource, model, nil, action, params, authority)}
    end
  end

  defp step(name, op, resource, model, attrs, action, params, authority) do
    %{
      name: name,
      op: op,
      resource: resource,
      model: model,
      attrs: attrs,
      action: action,
      params: params,
      authority: authority,
      fun: nil
    }
  end

  defp resolve_resource(resource_type) when is_binary(resource_type) do
    case Hawk.Plans.Registry.resolve(resource_type) do
      {:ok, resource} -> {:ok, resource}
      :error -> {:error, {:unknown_resource, resource_type}}
    end
  end

  defp load_member(resource, id, authority) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.one(authority: authority, filter: %{identity => id}) do
      {:ok, model} -> {:ok, model}
      :not_found -> {:error, {:not_found, Hawk.JsonApi.Schema.metadata(resource.__hawk_resource__(:model)).type, id}}
    end
  end

  @doc """
  Executes a plan in a single transaction under the reviewer's authority.
  All-or-nothing: any step failure rolls back the whole batch.

  The repo is resolved from the ops' resource readers; a plan batch runs in one
  transaction, so every op must share a single repo. `run/2` raises if the
  ops span more than one repo, since a transaction on one repo cannot roll
  back a write through another. Returns `{:ok, results_map}` or
  `{:error, failed_step_name, reason, prior_results}`.
  """
  @spec run(Plan.t(), Authority.t()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def run(%Plan{} = plan, %Authority{} = reviewer_authority) do
    case to_multi(plan, reviewer_authority) do
      {:ok, multi} -> Multi.execute(multi, resolve_repo(multi))
      {:error, reason} -> {:error, :setup, reason, %{}}
    end
  end

  @doc """
  Previews a plan's effects by executing it in a transaction and rolling
  back. Full fidelity including repo-level constraints. The review surface
  should label the result a *preview* — execution re-checks under the
  reviewer's authority.

  With a real Postgres repo, this opens a transaction, runs the `Hawk.Multi`,
  captures effects, and rolls back. With a test repo double (no real DB),
  the transaction is a no-op wrapper and the effects are captured from the
  in-memory execution.

  Returns `{:ok, effects_map}` or `{:error, failed_step_name, reason, prior_effects}`.
  """
  @spec preview(Plan.t(), Authority.t()) ::
          {:ok, map()} | {:error, atom(), term(), map()}
  def preview(%Plan{} = plan, %Authority{} = reviewer_authority) do
    case to_multi(plan, reviewer_authority) do
      {:ok, multi} ->
        repo = resolve_repo(multi)
        preview_execute(multi, repo)

      {:error, reason} ->
        {:error, :setup, reason, %{}}
    end
  end

  defp preview_execute(multi, repo) do
    if function_exported?(repo, :transaction, 1) and has_rollback?(repo) do
      preview_with_rollback(multi, repo)
    else
      # Test repo double: no real rollback needed, just execute and capture.
      Multi.execute(multi, repo)
    end
  end

  defp has_rollback?(repo) do
    Code.ensure_loaded?(repo) and function_exported?(repo, :rollback, 1)
  end

  defp preview_with_rollback(multi, repo) do
    {transaction_result, _discarded_capture} =
      Hawk.RepositoryBoundary.capture_broadcasts(fn ->
        repo.transaction(fn -> preview_multi(multi, repo) end)
      end)

    case transaction_result do
      {:error, {:ok, results}} -> {:ok, results}
      {:error, {:error, name, reason, prior}} -> {:error, name, reason, prior}
    end
  end

  defp preview_multi(multi, repo) do
    case Multi.execute(multi, repo) do
      {:ok, results} -> repo.rollback({:ok, results})
      {:error, name, reason, prior} -> repo.rollback({:error, name, reason, prior})
    end
  end

  # A plan batch runs in a single Ecto transaction, which can only coordinate
  # one repo: a transaction on repo A does not roll back a write through repo
  # B. So an atomic plan batch requires every op to share a single repo. We
  # resolve each op's repo from its resource facade reader and raise if they
  # diverge, rather than silently running a cross-repo batch that cannot
  # actually roll back. A reader that exposes no repo/0 is also rejected,
  # since a Hawk.Reader.Resource always provides one — a missing repo is a
  # contract violation, not a signal to bypass the guard.
  @doc false
  def resolve_repo(multi) do
    case repo_per_step(multi) do
      [] -> nil
      [repo | rest] -> enforce_single_repo!(rest, repo)
    end
  end

  defp repo_per_step(multi) do
    multi
    |> Multi.to_list()
    |> Enum.map(&resource_repo/1)
  end

  defp resource_repo(%{resource: resource}) do
    case resource.__hawk_resource__(:reader) do
      reader when is_atom(reader) and not is_nil(reader) ->
        if Code.ensure_loaded?(reader) and function_exported?(reader, :repo, 0) do
          reader.repo()
        else
          raise ArgumentError,
                "Hawk plan op on #{inspect(resource)} resolved reader #{inspect(reader)} " <>
                  "which does not expose repo/0; a Hawk.Reader.Resource always provides one"
        end

      other ->
        raise ArgumentError,
              "Hawk plan op on #{inspect(resource)} did not resolve a reader " <>
                "(got #{inspect(other)}); every plan op must back onto a Hawk resource with a reader"
    end
  end

  defp enforce_single_repo!(repos, repo) do
    Enum.each(repos, fn other ->
      unless other == repo do
        raise ArgumentError,
              "Hawk plan batches run in a single transaction and require all ops to " <>
                "share one repo; found #{inspect(repo)} and #{inspect(other)}. " <>
                "Split the plan by repo, or ensure every op's resource reader uses " <>
                "the same repo."
      end
    end)

    repo
  end
end

defmodule Hawk.RepositoryBoundary do
  @moduledoc """
  Enforcing persistence boundary for Hawk writer pipelines.

  Host applications provide the repo module. Hawk verifies mutation-context
  state before delegating to that repo and normalizes persistence results back
  into framework result tuples.
  """

  alias Ecto.Changeset
  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Hawk.Result

  @type audit_event :: %{
          operation: :insert | :update | :delete,
          authority: Authority.t(),
          model: struct()
        }

  @type repo :: module()
  @type opts :: keyword()

  @deferred_broadcasts_key {__MODULE__, :deferred_broadcasts}

  @doc false
  def capturing_broadcasts? do
    Process.get(@deferred_broadcasts_key, :not_capturing) != :not_capturing
  end

  @doc false
  def capture_broadcasts(fun) when is_function(fun, 0) do
    case Process.get(@deferred_broadcasts_key, :not_capturing) do
      :not_capturing ->
        Process.put(@deferred_broadcasts_key, [])

        try do
          {fun.(), @deferred_broadcasts_key |> Process.get([]) |> Enum.reverse()}
        after
          Process.delete(@deferred_broadcasts_key)
        end

      broadcasts ->
        {fun.(), {:nested, broadcasts}}
    end
  end

  @doc false
  def flush_broadcasts({:nested, _broadcasts}), do: :ok

  def flush_broadcasts(broadcasts) when is_list(broadcasts) do
    Enum.each(broadcasts, fn {pubsub, strategy, resource, operation, model} ->
      Hawk.PubSub.broadcast(pubsub, strategy, resource, operation, model)
    end)
  end

  @doc false
  def discard_broadcasts({:nested, broadcasts}) do
    Process.put(@deferred_broadcasts_key, broadcasts)
    :ok
  end

  def discard_broadcasts(_broadcasts), do: :ok

  @doc """
  Inserts the context changeset through the host repo.
  """
  @spec insert(MutationContext.t(), repo(), opts()) :: Result.t(struct())
  def insert(%MutationContext{} = context, repo, opts \\ []) do
    persist(context, repo, :insert, opts, fn ->
      repo.insert(context.changeset, repo_opts(opts))
    end)
  end

  @doc """
  Updates the context changeset through the host repo.

  No-op updates return the unchanged model without touching the repo or audit
  hook.
  """
  @spec update(MutationContext.t(), repo(), opts()) :: Result.t(struct())
  def update(context, repo, opts \\ [])

  def update(%MutationContext{changeset: %{changes: changes}} = context, _repo, _opts)
      when map_size(changes) == 0 do
    with :ok <- preflight(context) do
      {:ok, context.model}
    end
  end

  def update(%MutationContext{} = context, repo, opts) do
    with :ok <- preflight(context) do
      persist_preflighted(context, repo, :update, opts, fn ->
        repo.update(context.changeset, repo_opts(opts))
      end)
    end
  end

  @doc """
  Deletes the context model through the host repo.
  """
  @spec delete(MutationContext.t(), repo(), opts()) :: Result.t(struct())
  def delete(%MutationContext{} = context, repo, opts \\ []) do
    persist(context, repo, :delete, opts, fn ->
      repo.delete(context.model, repo_opts(opts))
    end)
  end

  defp persist(%MutationContext{} = context, repo, operation, opts, repo_fun) do
    with :ok <- preflight(context) do
      persist_preflighted(context, repo, operation, opts, repo_fun)
    end
  end

  defp persist_preflighted(context, repo, operation, opts, repo_fun) do
    repo.transaction(fn ->
      repo_fun.()
      |> normalize_repo_result(context, operation, opts)
    end)
    |> unwrap_transaction()
    |> broadcast_change(operation, opts)
  end

  # Broadcasts after the transaction commits so cross-process subscribers that
  # re-query immediately see the committed record. Only a successful write
  # broadcasts; invalid / unauthorized / error results pass through. No-op
  # updates (empty changes) return early from `update/3` and never reach here.
  defp broadcast_change({:ok, model} = result, operation, opts) do
    case Keyword.get(opts, :pubsub) do
      nil ->
        :ok

      pubsub when is_atom(pubsub) ->
        resource = Keyword.fetch!(opts, :resource)
        strategy = Keyword.get(opts, :topic_strategy) || Hawk.PubSub.DefaultTopics
        event_operation = if operation == :insert, do: :create, else: operation
        broadcast = {pubsub, strategy, resource, event_operation, model}

        case Process.get(@deferred_broadcasts_key, :not_capturing) do
          :not_capturing ->
            Hawk.PubSub.broadcast(pubsub, strategy, resource, event_operation, model)

          broadcasts ->
            Process.put(@deferred_broadcasts_key, [broadcast | broadcasts])
        end
    end

    result
  end

  defp broadcast_change(result, _operation, _opts), do: result

  defp preflight(%MutationContext{error: :invalid} = context), do: {:invalid, context}

  defp preflight(%MutationContext{error: :not_authorized} = context) do
    {:not_authorized, context}
  end

  defp preflight(%MutationContext{error: :none} = context) do
    validate_policy_marker!(context)
  end

  defp validate_policy_marker!(%MutationContext{policy_validated?: true}), do: :ok

  defp validate_policy_marker!(%MutationContext{}) do
    raise "write policy has not been validated"
  end

  defp normalize_repo_result({:ok, model}, context, operation, opts) do
    model = preserve_loaded_relations(context, model, operation)

    audit(context, operation, model, opts)
    {:ok, model}
  end

  defp normalize_repo_result({:error, %Changeset{} = changeset}, context, _operation, _opts) do
    context =
      context
      |> Map.put(:changeset, changeset)
      |> MutationContext.put_error(:invalid)

    Result.from_context(context, context.model)
  end

  defp normalize_repo_result({:error, message}, _context, _operation, _opts)
       when is_binary(message) do
    Result.error(message)
  end

  defp normalize_repo_result(result, _context, _operation, _opts) do
    raise "unsupported repo result: #{inspect(result)}"
  end

  defp unwrap_transaction({:ok, result}), do: result
  defp unwrap_transaction({:error, message}) when is_binary(message), do: Result.error(message)
  defp unwrap_transaction(result), do: result

  defp preserve_loaded_relations(context, model, operation)
       when operation in [:insert, :update] do
    model
    |> schema_associations()
    |> Enum.reduce(model, fn association, model ->
      preserve_loaded_relation(context, model, association)
    end)
  end

  defp preserve_loaded_relations(_context, model, _operation), do: model

  defp preserve_loaded_relation(context, model, association) do
    case schema_association(model, association) do
      %Ecto.Association.BelongsTo{} = belongs_to ->
        preserve_belongs_to(context, model, belongs_to)

      _other ->
        model
    end
  end

  defp preserve_belongs_to(context, model, association) do
    with true <- Map.has_key?(context.changeset.changes, association.owner_key),
         {:ok, relation} <- Map.fetch(context.attrs, association.field),
         true <- relation_matches_owner_key?(model, relation, association) do
      Map.put(model, association.field, relation)
    else
      _other -> model
    end
  end

  defp relation_matches_owner_key?(model, nil, association) do
    Map.get(model, association.owner_key) == nil
  end

  defp relation_matches_owner_key?(model, relation, association) when is_struct(relation) do
    Map.get(model, association.owner_key) == Map.get(relation, association.related_key)
  end

  defp relation_matches_owner_key?(_model, _relation, _association), do: false

  defp schema_associations(%module{}) do
    if function_exported?(module, :__schema__, 1) do
      module.__schema__(:associations)
    else
      []
    end
  end

  defp schema_association(%module{}, association) do
    module.__schema__(:association, association)
  end

  defp audit(context, operation, model, opts) do
    case Keyword.get(opts, :audit) do
      nil ->
        :ok

      audit_fun when is_function(audit_fun, 1) ->
        audit_fun.(%{operation: operation, authority: context.authority, model: model})
        :ok
    end
  end

  defp repo_opts(opts) do
    Keyword.get(opts, :repo_opts, [])
  end
end

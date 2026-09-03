defmodule Hawk.Query.Validation do
  @moduledoc """
  Compile-time and strict validation for `Hawk.Query` declarations.
  """

  @type mode :: :compile | :strict

  @doc """
  Validates local query options that do not depend on module body declarations.
  """
  @spec validate_local!(map()) :: :ok
  def validate_local!(metadata) do
    validate_name!(metadata.name)
    validate_source!(metadata.source)
    validate_pagination!(metadata.pagination)
    validate_transaction!(metadata.transaction)
  end

  @doc """
  Validates a query declaration.
  """
  @spec validate!(map(), mode()) :: :ok
  def validate!(metadata, mode \\ :compile) when mode in [:compile, :strict] do
    validate_local!(metadata)
    validate_prepare!(metadata, mode)

    policy_available? = available?(metadata.policy, :policy, mode)

    if policy_available? do
      validate_functions!(metadata.policy, :policy, read_filter: 1, __hawk_policy__: 0)

      if mode == :strict do
        validate_filter_mappings!(metadata)
        validate_policy_filters!(metadata.policy, metadata)
        validate_rank!(metadata)
      end
    end

    :ok
  end

  defp validate_name!(name) when is_atom(name) and not is_nil(name), do: :ok

  defp validate_name!(_name) do
    raise ArgumentError, "Hawk query :name must be a non-empty atom"
  end

  defp validate_source!(source) when is_atom(source) do
    case Code.ensure_compiled(source) do
      {:module, ^source} -> validate_source_facade!(source)
      _other -> raise ArgumentError, "Hawk query :source #{inspect(source)} is not available"
    end
  end

  defp validate_source!(source) do
    raise ArgumentError,
          "Hawk query :source must be a Hawk.Resource facade, got: #{inspect(source)}"
  end

  defp validate_source_facade!(source) do
    unless function_exported?(source, :__hawk_resource__, 1) do
      raise ArgumentError,
            "Hawk query :source #{inspect(source)} must be a Hawk.Resource facade"
    end

    unless source.__hawk_resource__(:json_api) do
      raise ArgumentError,
            "Hawk query :source #{inspect(source)} must expose JSON:API for resource results"
    end

    :ok
  end

  defp validate_pagination!(pagination) when pagination in [:offset], do: :ok

  defp validate_pagination!(pagination) do
    raise ArgumentError, "Hawk query :pagination must be :offset, got: #{inspect(pagination)}"
  end

  defp validate_transaction!(transaction) when transaction in [true, false], do: :ok

  defp validate_transaction!(transaction) do
    raise ArgumentError, "Hawk query :transaction must be a boolean, got: #{inspect(transaction)}"
  end

  defp validate_prepare!(%{transaction: true}, _mode), do: :ok
  defp validate_prepare!(%{module: nil}, _mode), do: :ok

  defp validate_prepare!(%{module: module, transaction: false}, :strict) do
    if Code.ensure_loaded?(module) and function_exported?(module, :prepare, 3) do
      raise ArgumentError,
            "Hawk query #{inspect(module)} defines prepare/3 but did not declare transaction: true"
    end
  end

  defp validate_prepare!(_metadata, _mode), do: :ok

  defp available?(module, key, :strict) when is_atom(module) do
    unless compiled?(module) do
      raise ArgumentError, "Hawk query #{key} module #{inspect(module)} is not available"
    end

    true
  end

  defp available?(module, key, :compile) when is_atom(module) do
    if compiled?(module) do
      true
    else
      warn_missing(key, module)
      false
    end
  end

  defp warn_missing(key, module) do
    IO.warn(
      "Hawk query #{key} module #{inspect(module)} is not available yet; " <>
        "skipping its contract validation. Run `mix hawk.validate` to enforce."
    )
  end

  defp compiled?(module), do: match?({:module, ^module}, Code.ensure_compiled(module))

  defp validate_filter_mappings!(metadata) do
    source_filter_keys = metadata.source.__hawk_resource__(:reader) |> reader_filter_keys()

    metadata
    |> Map.get(:source_filters, %{})
    |> Enum.reject(fn {_query_key, source_key} ->
      MapSet.member?(source_filter_keys, source_key)
    end)
    |> case do
      [] ->
        :ok

      [{query_key, source_key} | _rest] ->
        raise ArgumentError,
              "Hawk query filter #{inspect(query_key)} maps to source filter #{inspect(source_key)}, which is not declared by #{inspect(metadata.source)}"
    end
  end

  defp validate_policy_filters!(policy, metadata) do
    declared_filter_keys = Map.get(metadata, :filter_keys, MapSet.new())

    policy
    |> policy_read_filters()
    |> Enum.reject(&MapSet.member?(declared_filter_keys, &1))
    |> case do
      [] ->
        :ok

      [key] ->
        raise ArgumentError,
              "Hawk query policy module #{inspect(policy)} read filter #{inspect(key)} must map to a declared query filter"

      keys ->
        inspected_keys = Enum.map_join(keys, ", ", &inspect/1)

        raise ArgumentError,
              "Hawk query policy module #{inspect(policy)} read filters #{inspected_keys} must map to declared query filters"
    end
  end

  defp validate_rank!(%{rank: nil}), do: :ok

  defp validate_rank!(metadata) do
    source_sort_keys = metadata.source.__hawk_resource__(:reader) |> reader_sort_keys()
    source_identity = metadata.source.__hawk_resource__(:identity)
    rank = metadata.rank

    unless rank.tie_breaker == source_identity do
      raise ArgumentError,
            "Hawk query rank #{inspect(rank.name)} tie breaker #{inspect(rank.tie_breaker)} must be the source resource identity #{inspect(source_identity)}"
    end

    rank.sort
    |> Keyword.values()
    |> Enum.each(fn key ->
      unless MapSet.member?(source_sort_keys, key) do
        raise ArgumentError,
              "Hawk query rank #{inspect(rank.name)} sort key #{inspect(key)} must be declared by source reader"
      end
    end)
  end

  defp reader_filter_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :filter_keys, 0) do
      MapSet.new(reader.filter_keys())
    else
      MapSet.new()
    end
  end

  defp reader_sort_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :sort_keys, 0) do
      MapSet.new(reader.sort_keys())
    else
      MapSet.new()
    end
  end

  defp policy_read_filters(policy) do
    policy.__hawk_policy__()
    |> Map.fetch!(:read)
    |> Enum.flat_map(&policy_role_filter_keys/1)
    |> Enum.uniq()
  end

  defp policy_role_filter_keys({_role, :all}), do: []

  defp policy_role_filter_keys({_role, {:scoped, scopes, filter}}) do
    Enum.map(scopes, &policy_scope_filter_key/1) ++ Map.keys(filter)
  end

  defp policy_scope_filter_key({filter_key, _scope_key}), do: filter_key
  defp policy_scope_filter_key(scope_key) when is_atom(scope_key), do: scope_key

  defp validate_functions!(module, key, functions) do
    Enum.each(functions, fn {function, arity} ->
      unless function_exported?(module, function, arity) do
        raise ArgumentError,
              "Hawk query #{key} module #{inspect(module)} must define #{function}/#{arity}"
      end
    end)
  end
end

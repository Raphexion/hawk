defmodule Hawk.Query do
  @moduledoc """
  Declarative read-side extension point for policy-safe resource queries.

  A Query derives a read-only collection from a declared Hawk resource. Hawk
  checks the Query policy, maps the Query's declared filters to source Reader
  filters, applies the declared rank, and delegates execution to the source
  resource so source policy and canonical pagination stay in control.
  """

  alias Hawk.Filter
  alias Hawk.Query.Validation

  @allowed_options MapSet.new([:authority, :context, :fields, :filter, :page, :params, :preloads, :select])

  @doc """
  Fetches a page from a Hawk query declaration.
  """
  def page(query, opts) when is_atom(query), do: execute(query, :page, opts)

  defp execute(query, operation, opts) do
    validate!(query, :strict)

    metadata = metadata(query)
    opts = normalize_options(opts)
    validate_page!(metadata, opts)

    authority = Map.fetch!(opts, :authority)

    case metadata.policy.read_filter(authority) do
      :none ->
        {:error, Hawk.Error.not_authorized("Query access denied")}

      query_policy_filter ->
        with {:ok, params} <- cast_params(query, Map.fetch!(opts, :params)) do
          source_filter =
            metadata
            |> map_query_filter!(query_policy_filter)
            |> Filter.and(map_query_filter!(metadata, Map.fetch!(opts, :filter)))

          do_execute(metadata, operation, %{opts | params: params}, source_filter)
        end
    end
  end

  defp do_execute(%{transaction: true} = metadata, operation, opts, source_filter) do
    repo = metadata.source.__hawk_resource__(:reader).repo()

    case repo.transaction(fn -> transaction_body(repo, metadata, operation, opts, source_filter) end) do
      {:ok, result} -> result
      {:error, %Hawk.Error{} = error} -> {:error, error}
    end
  end

  defp do_execute(metadata, operation, opts, source_filter) do
    execute_source(metadata, operation, opts, source_filter)
  end

  defp transaction_body(repo, metadata, operation, opts, source_filter) do
    case prepare(metadata, repo, opts.params, Map.get(opts, :context, %{})) do
      :ok -> execute_source(metadata, operation, opts, source_filter)
      {:error, %Hawk.Error{} = error} -> repo.rollback(error)
    end
  end

  defp execute_source(metadata, operation, opts, source_filter) do
    metadata
    |> source_opts(opts, source_filter)
    |> then(&apply(metadata.source, operation, [&1]))
  end

  defp prepare(metadata, repo, params, context) do
    if function_exported?(metadata.module, :prepare, 3) do
      metadata.module.prepare(repo, params, context)
    else
      :ok
    end
  end

  defp source_opts(metadata, opts, source_filter) do
    opts
    |> Map.take([:authority, :context, :fields, :page, :preloads, :select])
    |> Map.put(:filter, source_filter)
    |> maybe_put_rank_sort(metadata.rank)
    |> Map.to_list()
  end

  defp maybe_put_rank_sort(opts, nil), do: opts
  defp maybe_put_rank_sort(opts, rank), do: Map.put(opts, :sort, rank.sort)

  defp cast_params(query, params) do
    if function_exported?(query, :cast_params, 1) do
      query.cast_params(params)
    else
      {:ok, params}
    end
  end

  defp normalize_options(opts) when is_list(opts), do: opts |> Map.new() |> normalize_options()

  defp normalize_options(opts) when is_map(opts) do
    unknown_options =
      opts
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(@allowed_options, &1))
      |> Enum.sort()

    case unknown_options do
      [] -> :ok
      [option] -> raise ArgumentError, "unknown query option #{inspect(option)}"
      options -> raise ArgumentError, "unknown query options #{inspect(options)}"
    end

    opts
    |> Map.put_new(:params, %{})
    |> Map.put_new(:filter, :all)
  end

  defp validate_page!(%{pagination: :offset, name: name}, %{page: %{after: cursor}})
       when not is_nil(cursor) do
    raise ArgumentError,
          "Hawk query #{inspect(name)} supports offset pagination only; page[after] is not supported"
  end

  defp validate_page!(_metadata, _opts), do: :ok

  defp map_query_filter!(_metadata, :all), do: :all
  defp map_query_filter!(_metadata, :none), do: :none

  defp map_query_filter!(metadata, filter) do
    filter
    |> Filter.normalize()
    |> map_normalized_query_filter!(metadata.source_filters, metadata.filter_keys)
  end

  defp map_normalized_query_filter!({:and, left, right}, source_filters, filter_keys) do
    {:and, map_normalized_query_filter!(left, source_filters, filter_keys),
     map_normalized_query_filter!(right, source_filters, filter_keys)}
  end

  defp map_normalized_query_filter!({:or, left, right}, source_filters, filter_keys) do
    {:or, map_normalized_query_filter!(left, source_filters, filter_keys),
     map_normalized_query_filter!(right, source_filters, filter_keys)}
  end

  defp map_normalized_query_filter!(filter, source_filters, filter_keys) when is_map(filter) do
    filter
    |> Enum.map(fn {key, value} ->
      unless MapSet.member?(filter_keys, key) do
        raise ArgumentError, "unknown query filter key #{inspect(key)}"
      end

      {Map.fetch!(source_filters, key), value}
    end)
    |> Map.new()
  end

  @doc """
  Validates a compiled Hawk query declaration.
  """
  def validate!(query, mode \\ :compile) when is_atom(query) do
    unless Code.ensure_loaded?(query) and function_exported?(query, :__hawk_query__, 1) do
      raise ArgumentError, "#{inspect(query)} is not a Hawk.Query declaration"
    end

    query
    |> metadata()
    |> Validation.validate!(mode)
  end

  @doc """
  Returns the metadata for a compiled Hawk query declaration.
  """
  def metadata(query) when is_atom(query) do
    %{
      name: query.__hawk_query__(:name),
      module: query,
      source: query.__hawk_query__(:source),
      policy: query.__hawk_query__(:policy),
      transaction: query.__hawk_query__(:transaction),
      pagination: query.__hawk_query__(:pagination),
      filter_keys: query.__hawk_query__(:filter_keys),
      source_filters: query.__hawk_query__(:source_filters),
      rank: query.__hawk_query__(:rank)
    }
  end

  @doc """
  Declares a source-backed query filter.

  Query filters are the only keys a Query policy may mention. Each query filter
  maps to a filter declared by the source resource Reader; by default the source
  filter key is the same as the Query key.
  """
  defmacro filter(key, opts \\ []) when is_atom(key) and is_list(opts) do
    source = Keyword.get(opts, :source, key)

    unless is_atom(source) do
      raise ArgumentError, "Hawk query filter #{inspect(key)} :source must be an atom"
    end

    quote do
      @hawk_query_filters {unquote(key), unquote(source)}
    end
  end

  @doc """
  Declares the default deterministic ranking for a Query.

  The current rank vocabulary is intentionally constrained to source Reader sort
  keys. Hawk appends the tie breaker when it is not already present.
  """
  defmacro rank(name, opts) when is_atom(name) and is_list(opts) do
    sort = Keyword.fetch!(opts, :sort)
    tie_breaker = Keyword.get(opts, :tie_breaker)
    rank = normalize_rank!(name, sort, tie_breaker)

    quote do
      @hawk_query_ranks unquote(Macro.escape(rank))
    end
  end

  @doc """
  Declares a Hawk query.
  """
  defmacro __using__(opts) do
    env = __CALLER__
    caller = env.module

    name = Keyword.fetch!(opts, :name)
    source = opts |> Keyword.fetch!(:source) |> Macro.expand(env)
    policy = Module.concat(caller, Policy)
    transaction = Keyword.get(opts, :transaction, false)
    pagination = Keyword.get(opts, :pagination, :offset)

    metadata = %{
      name: name,
      module: caller,
      source: source,
      policy: policy,
      transaction: transaction,
      pagination: pagination
    }

    Validation.validate_local!(metadata)

    quote do
      @behaviour Hawk.Query

      import Hawk.Query, only: [filter: 1, filter: 2, rank: 2]
      Module.register_attribute(__MODULE__, :hawk_query_filters, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_query_ranks, accumulate: true)
      @hawk_query_metadata unquote(Macro.escape(metadata))
      @before_compile Hawk.Query

      def __hawk_query__(:name), do: unquote(name)
      def __hawk_query__(:source), do: unquote(source)
      def __hawk_query__(:policy), do: unquote(policy)
      def __hawk_query__(:transaction), do: unquote(transaction)
      def __hawk_query__(:pagination), do: unquote(pagination)
      def __hawk_query__(:filter_keys), do: Hawk.Query.filter_keys(__MODULE__)
      def __hawk_query__(:source_filters), do: Hawk.Query.source_filters(__MODULE__)
      def __hawk_query__(:metadata), do: Hawk.Query.metadata(__MODULE__)

      def page(opts), do: Hawk.Query.page(__MODULE__, opts)
    end
  end

  defmacro __before_compile__(env) do
    filters = env.module |> Module.get_attribute(:hawk_query_filters) |> Enum.reverse()
    ranks = env.module |> Module.get_attribute(:hawk_query_ranks) |> Enum.reverse()
    rank = validate_rank_declarations!(ranks)
    validate_filter_declarations!(filters)

    metadata =
      env.module
      |> Module.get_attribute(:hawk_query_metadata)
      |> Map.put(:filter_keys, filters |> Keyword.keys() |> MapSet.new())
      |> Map.put(:source_filters, Map.new(filters))
      |> Map.put(:rank, rank)

    Validation.validate!(metadata, :compile)

    quote do
      def __hawk_query__(:declared_filters), do: unquote(Macro.escape(filters))
      def __hawk_query__(:rank), do: unquote(Macro.escape(rank))
    end
  end

  def filter_keys(query) when is_atom(query) do
    query
    |> declared_filters()
    |> Keyword.keys()
    |> MapSet.new()
  end

  def source_filters(query) when is_atom(query) do
    query
    |> declared_filters()
    |> Map.new()
  end

  defp normalize_rank!(name, sort, tie_breaker) do
    validate_rank_sort!(name, sort)

    unless is_atom(tie_breaker) and not is_nil(tie_breaker) do
      raise ArgumentError, "Hawk query rank #{inspect(name)} requires :tie_breaker"
    end

    sort = if tie_breaker in Keyword.values(sort), do: sort, else: sort ++ [asc: tie_breaker]

    %{name: name, sort: sort, tie_breaker: tie_breaker}
  end

  defp validate_rank_sort!(name, sort) when is_list(sort) do
    Enum.each(sort, fn
      {direction, key} when direction in [:asc, :desc] and is_atom(key) -> :ok
      other -> raise ArgumentError, "Hawk query rank #{inspect(name)} has invalid sort clause #{inspect(other)}"
    end)
  end

  defp validate_rank_sort!(name, _sort) do
    raise ArgumentError, "Hawk query rank #{inspect(name)} :sort must be a keyword list"
  end

  defp validate_rank_declarations!([]), do: nil
  defp validate_rank_declarations!([rank]), do: rank

  defp validate_rank_declarations!([rank | _rest]) do
    raise ArgumentError, "Hawk query declares multiple ranks; only one rank is supported, first: #{inspect(rank.name)}"
  end

  defp validate_filter_declarations!(filters) do
    duplicate_keys =
      filters
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case duplicate_keys do
      [] -> :ok
      [key] -> raise ArgumentError, "duplicate Hawk query filter #{inspect(key)}"
      keys -> raise ArgumentError, "duplicate Hawk query filters #{inspect(keys)}"
    end
  end

  defp declared_filters(query) do
    if Code.ensure_loaded?(query) and function_exported?(query, :__hawk_query__, 1) do
      query.__hawk_query__(:declared_filters)
    else
      []
    end
  rescue
    FunctionClauseError -> []
  end

  @callback cast_params(map()) :: {:ok, map()} | {:error, Hawk.Error.t()}
  @callback prepare(module(), map(), map()) :: :ok | {:error, Hawk.Error.t()}

  @optional_callbacks cast_params: 1, prepare: 3
end

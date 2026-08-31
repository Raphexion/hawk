defmodule Hawk.Reader do
  @moduledoc """
  Small runtime for resource reader modules.

  This module handles the common read flow: option normalization, policy/caller
  filter composition, key validation, direct-field filter compilation, default
  sorting, limit application, and repo calls.
  """

  import Ecto.Query

  alias Hawk.Filter
  alias Hawk.Reader.Cursor
  alias Hawk.Reader.FilterCompiler
  alias Hawk.Reader.JoinPlan
  alias Hawk.Reader.Page
  alias Hawk.Reader.Preloader

  @allowed_options MapSet.new([:authority, :context, :fields, :filter, :page, :preloads, :select, :sort])
  @sort_dirs [:asc, :desc, :asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last]

  @type config :: %{
          required(:repo) => module(),
          required(:schema) => module(),
          required(:filter_keys) => Enumerable.t(),
          required(:read_filter) => (term() -> Filter.t()),
          optional(:filter_handlers) => FilterCompiler.handlers(),
          optional(:coordinate_filters) => %{optional(atom()) => Hawk.Reader.Coordinates.options()},
          optional(:join_plan) => [JoinPlan.rule()],
          optional(:forced_filter) => Filter.t(),
          optional(:preload_keys) => Enumerable.t(),
          optional(:preload_readers) => %{optional(atom()) => module()},
          optional(:preload_options) => %{optional(atom()) => map()},
          optional(:scope) => (Ecto.Query.t(), map(), map() -> Ecto.Query.t()),
          optional(:sort_keys) => Enumerable.t(),
          optional(:default_sort) => keyword(atom()),
          optional(:default_page_size) => pos_integer() | nil,
          optional(:max_page_size) => pos_integer() | nil
        }

  @doc """
  Fetches all records for a reader config and options.
  """
  @spec all(config(), keyword() | map()) :: [struct()]
  def all(config, opts) do
    opts = normalize_options(opts)

    Preloader.validate_preloads!(
      opts.preloads,
      Map.get(config, :preload_keys, []),
      config.schema,
      Map.get(config, :preload_readers, %{})
    )

    config
    |> build_query(opts)
    |> config.repo.all()
    |> Preloader.preload(
      config.repo,
      opts.preloads,
      Map.get(config, :preload_keys, []),
      opts.authority,
      Map.get(config, :preload_readers, %{}),
      Map.get(config, :preload_options, %{}),
      opts.fields
    )
  end

  @doc """
  Fetches a bounded page and one internal look-ahead row.

  The look-ahead row is removed from `entries` and represented by `has_more?`
  and an opaque forward `next_cursor`.
  """
  @spec page(config(), keyword() | map()) :: Page.t()
  def page(config, opts) do
    opts = normalize_options(opts)
    page = normalized_page(config, opts.page)
    size = Map.get(page, :size)
    sort = effective_sort(config, opts.sort)
    validate_sort_keys!(config, opts.sort)

    {results, total_count} =
      if page[:total] do
        case build_counted_page_query(config, opts, sort, page) do
          {:ok, counted_query} ->
            run_counted_page_query(counted_query, config.repo, config.schema)

          :fallback ->
            results =
              config
              |> build_query_from_normalized(%{opts | page: lookahead_page(page)}, sort)
              |> config.repo.all()

            {results, count(config, opts)}
        end
      else
        results =
          config
          |> build_query_from_normalized(%{opts | page: lookahead_page(page)}, sort)
          |> config.repo.all()

        {results, nil}
      end

    {entries, has_more?} = trim_lookahead(results, size)

    entries =
      Preloader.preload(
        entries,
        config.repo,
        opts.preloads,
        Map.get(config, :preload_keys, []),
        opts.authority,
        Map.get(config, :preload_readers, %{}),
        Map.get(config, :preload_options, %{}),
        opts.fields
      )

    next_cursor = next_cursor(entries, has_more?, sort)

    %Page{
      entries: entries,
      has_more?: has_more?,
      next_cursor: next_cursor,
      page: if(has_more? and is_nil(next_cursor), do: Map.put(page, :cursor_unavailable, true), else: page),
      total_count: total_count
    }
  end

  @doc """
  Fetches exactly one record, returning `:not_found` when none exists.
  """
  @spec one(config(), keyword() | map()) :: {:ok, struct()} | :not_found
  def one(config, opts) do
    opts = normalize_options(opts)

    Preloader.validate_preloads!(
      opts.preloads,
      Map.get(config, :preload_keys, []),
      config.schema,
      Map.get(config, :preload_readers, %{})
    )

    results =
      config
      |> build_query(%{opts | page: %{size: 2}, preloads: []})
      |> config.repo.all()

    case results do
      [model] ->
        [model]
        |> Preloader.preload(
          config.repo,
          opts.preloads,
          Map.get(config, :preload_keys, []),
          opts.authority,
          Map.get(config, :preload_readers, %{}),
          Map.get(config, :preload_options, %{}),
          opts.fields
        )
        |> List.first()
        |> then(&{:ok, &1})

      [] ->
        :not_found

      _results ->
        raise "expected one result, got 2"
    end
  end

  @doc """
  Counts records for the authorized, unpaginated reader query.
  """
  @spec count(config(), keyword() | map()) :: non_neg_integer()
  def count(config, opts) do
    opts = normalize_options(opts)
    authority = Map.fetch!(opts, :authority)
    caller_filter = Map.fetch!(opts, :filter)
    validate_sort_keys!(config, Map.get(opts, :sort, []))

    query =
      config.schema
      |> from(as: :root)
      |> apply_authorized_filter(config, authority, caller_filter, [])
      |> apply_scope(config, opts, %{authority: authority})

    distinct_root_count(query, config.repo, identity(config))
  end

  @doc """
  Builds the query for a reader call.
  """
  @spec build_query(config(), keyword() | map()) :: Ecto.Query.t()
  def build_query(config, opts) do
    opts = normalize_options(opts)
    page = normalized_page(config, Map.fetch!(opts, :page))
    requested_sort = Map.get(opts, :sort, [])
    validate_sort_keys!(config, requested_sort)
    sort = effective_sort(config, requested_sort)

    build_query_from_normalized(config, %{opts | page: page}, sort)
  end

  @doc """
  Applies a reader's policy/filter/join declarations to an existing query.

  This is used for policy-aware preloads where the associated resource reader
  owns the joins and custom filter handlers needed to enforce visibility.
  """
  @spec apply_authorized_filter(Ecto.Query.t(), config(), term(), Filter.t(), atom() | [atom()]) ::
          Ecto.Query.t()
  def apply_authorized_filter(query, config, authority, caller_filter \\ :all, sort_key \\ :id) do
    filter = authorized_filter(config, authority, caller_filter)

    Filter.validate_keys!(filter, config.filter_keys)

    rules = Map.get(config, :join_plan, [])
    handlers = Map.get(config, :filter_handlers, %{})

    query
    |> JoinPlan.apply(rules, filter, sort_key)
    |> FilterCompiler.compile(
      config.schema,
      filter,
      handlers,
      Map.get(config, :coordinate_filters, %{}),
      JoinPlan.trigger_keys(rules)
    )
  end

  @doc """
  Applies a reader's resource-owned query shaping hook.

  Reader scopes are for projections or joins that belong to the resource shape,
  not for authorization; policy filters are applied before this hook.
  """
  @spec apply_scope(Ecto.Query.t(), config(), map(), map()) :: Ecto.Query.t()
  def apply_scope(query, config, params, opts) do
    case Map.get(config, :scope) do
      scope when is_function(scope, 3) -> scope.(query, params, opts)
      _ -> query
    end
  end

  @doc false
  def distinct_root_count(query, repo, identity) when is_atom(repo) and is_atom(identity) do
    query
    |> exclude(:order_by)
    |> exclude(:select)
    |> select([root: row], field(row, ^identity))
    |> distinct(true)
    |> subquery()
    |> repo.aggregate(:count)
  end

  @doc false
  def identity(config), do: Map.get_lazy(config, :identity, fn -> Hawk.JsonApi.Schema.identity(config.schema) end)

  defp authorized_filter(config, authority, caller_filter) do
    caller_filter
    |> Filter.and(config.read_filter.(authority))
    |> Filter.and(Map.get(config, :forced_filter, :all))
  end

  defp normalize_options(opts) when is_list(opts) do
    opts
    |> Map.new()
    |> normalize_options()
  end

  defp normalize_options(opts) when is_map(opts) do
    unknown_options =
      opts
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(@allowed_options, &1))
      |> Enum.sort()

    case unknown_options do
      [] -> :ok
      [option] -> raise ArgumentError, "unknown reader option #{inspect(option)}"
      options -> raise ArgumentError, "unknown reader options #{inspect(options)}"
    end

    %{
      authority: Map.fetch!(opts, :authority),
      context: Map.get(opts, :context, %{}),
      fields: normalize_fields(Map.get(opts, :fields, %{})),
      filter: Map.get(opts, :filter, :all),
      page: normalize_page(Map.get(opts, :page, %{})),
      preloads: Map.get(opts, :preloads, []),
      select: normalize_select(Map.get(opts, :select)),
      sort: normalize_sort(Map.get(opts, :sort, []))
    }
  end

  defp normalize_fields(fields) when is_map(fields), do: fields
  defp normalize_fields(fields), do: raise(ArgumentError, "fields must be a map, got: #{inspect(fields)}")

  defp normalize_select(nil), do: nil

  defp normalize_select(fields) when is_list(fields) do
    Enum.each(fields, fn
      field when is_atom(field) -> :ok
      field -> raise ArgumentError, "select fields must be atoms, got: #{inspect(field)}"
    end)

    Enum.uniq(fields)
  end

  defp normalize_select(fields), do: raise(ArgumentError, "select must be a list of atoms, got: #{inspect(fields)}")

  defp normalize_page(page) when is_map(page) do
    reject_smuggled_sort_keys!(page)
    Map.take(page, [:size, :number, :total, :after])
  end

  # Sorting used to ride inside :page as column/dir. It is now a first-class
  # :sort option, so a page map carrying those (or the unused :cursor) is a
  # stale caller — reject it loudly instead of silently dropping the sort.
  defp reject_smuggled_sort_keys!(page) do
    Enum.each([:column, :dir, :cursor], fn key ->
      if Map.has_key?(page, key) do
        raise ArgumentError,
              "Hawk reader :page no longer carries #{inspect(key)}; pass sort as a " <>
                "separate :sort option (a keyword list of {dir, column})"
      end
    end)
  end

  # Sort is a first-class reader option, kept separate from pagination: a
  # sort is a keyword list of `{dir, column}` (the same shape Ecto `order_by`
  # takes), or `[]` to mean "apply the reader's default_sort". Directions are
  # validated here so a bad dir fails before it reaches the query.
  defp normalize_sort(sort) when is_list(sort) do
    Enum.each(sort, fn
      {dir, column} when dir in @sort_dirs and is_atom(column) -> :ok
      other -> raise ArgumentError, "invalid sort clause #{inspect(other)}; expected {dir, column}"
    end)

    sort
  end

  defp apply_default_page_size(%{size: nil} = page, default_page_size),
    do: apply_default_page_size(Map.delete(page, :size), default_page_size)

  defp apply_default_page_size(page, nil), do: page
  defp apply_default_page_size(%{size: _size} = page, _default_page_size), do: page

  defp apply_default_page_size(page, default_page_size) when is_integer(default_page_size),
    do: Map.put(page, :size, default_page_size)

  defp enforce_max_page_size!(%{size: nil} = page, _max_page_size), do: page
  defp enforce_max_page_size!(page, nil), do: page

  defp enforce_max_page_size!(%{size: size} = page, max_page_size)
       when is_integer(size) and is_integer(max_page_size) and size <= max_page_size,
       do: page

  defp enforce_max_page_size!(%{size: size}, max_page_size) do
    raise ArgumentError, "page size #{inspect(size)} exceeds maximum #{inspect(max_page_size)}"
  end

  defp validate_sort_keys!(config, sort) do
    sort_keys =
      config
      |> Map.get(:sort_keys, [:id])
      |> Enum.to_list()
      |> case do
        [] -> [:id]
        keys -> keys
      end

    sort
    |> Keyword.values()
    |> Enum.each(fn column ->
      unless column in sort_keys do
        raise ArgumentError, "unsupported sort column #{inspect(column)}"
      end
    end)
  end

  defp sort_order(_config, [{_dir, column} | _] = sort) when is_atom(column), do: sort

  defp sort_order(config, []) do
    case Map.get(config, :default_sort, asc: identity(config)) do
      [] -> [asc: identity(config)]
      sort -> sort
    end
  end

  defp effective_sort(config, requested_sort) do
    sort = sort_order(config, requested_sort)
    identity = identity(config)

    if identity in Keyword.values(sort) do
      sort
    else
      sort ++ [{tie_break_direction(sort), identity}]
    end
  end

  defp tie_break_direction(sort) do
    case List.last(sort) do
      {direction, _field} when direction in [:desc, :desc_nulls_first, :desc_nulls_last] -> :desc
      _other -> :asc
    end
  end

  defp sort_columns(sort), do: Keyword.values(sort)

  defp apply_select(query, nil), do: query

  defp apply_select(query, fields) do
    select(query, [root: row], struct(row, ^fields))
  end

  defp build_query_from_normalized(config, opts, sort) do
    page = Map.fetch!(opts, :page)

    config
    |> build_base_query_from_normalized(opts, sort)
    |> apply_select(cursor_select(Map.get(opts, :select), sort))
    |> apply_cursor(page, sort, config.schema)
    |> apply_sort(sort)
    |> apply_offset(page)
    |> apply_limit(page)
  end

  defp build_counted_page_query(config, opts, sort, page) do
    fields = cursor_select(Map.get(opts, :select), sort) || config.schema.__schema__(:fields)
    lookahead = lookahead_page(page)
    base_query = build_base_query_from_normalized(config, opts, sort)

    if is_nil(base_query.select) do
      counted =
        base_query
        |> apply_select(fields)
        |> subquery()
        |> then(
          &from(row in &1,
            select:
              merge(map(row, ^fields), %{
                __hawk_total_count__: over(count())
              })
          )
        )

      query =
        from(row in subquery(counted),
          as: :root,
          select: %{
            entry: map(row, ^fields),
            total_count: field(row, :__hawk_total_count__)
          }
        )
        |> apply_cursor(page, sort, config.schema)
        |> apply_sort(sort)
        |> apply_offset(lookahead)
        |> apply_limit(lookahead)

      {:ok, query}
    else
      :fallback
    end
  end

  defp run_counted_page_query(query, repo, schema) do
    case repo.all(query) do
      [] ->
        {[], nil}

      rows ->
        entries =
          Enum.map(rows, &load_counted_entry(&1.entry, schema, repo.__adapter__(), query.prefix))

        {entries, rows |> hd() |> Map.fetch!(:total_count)}
    end
  end

  defp load_counted_entry(entry, schema, adapter, prefix) do
    loaded =
      Map.new(entry, fn {field, value} ->
        type = schema.__schema__(:type, field)
        {:ok, loaded_value} = Ecto.Type.adapter_load(adapter, type, value)
        {field, loaded_value}
      end)

    schema
    |> struct(loaded)
    |> Ecto.put_meta(state: :loaded, source: schema.__schema__(:source), prefix: prefix)
  end

  defp build_base_query_from_normalized(config, opts, sort) do
    authority = Map.fetch!(opts, :authority)
    caller_filter = Map.fetch!(opts, :filter)

    config.schema
    |> from(as: :root)
    |> apply_authorized_filter(config, authority, caller_filter, sort_columns(sort))
    |> apply_scope(config, opts, %{authority: authority})
    |> maybe_deduplicate_roots(config, authority, caller_filter, sort)
  end

  defp maybe_deduplicate_roots(query, config, authority, caller_filter, sort) do
    filter_keys =
      config
      |> authorized_filter(authority, caller_filter)
      |> Filter.normalize()
      |> Filter.keys()

    sort_keys = MapSet.new(sort_columns(sort))

    multiplying_join? =
      config
      |> Map.get(:join_plan, [])
      |> Enum.any?(fn rule ->
        rule.multiplies_roots and
          (not MapSet.disjoint?(rule.when_filter, filter_keys) or
             not MapSet.disjoint?(rule.when_sort, sort_keys))
      end)

    if multiplying_join?, do: distinct(query, true), else: query
  end

  defp cursor_select(nil, _sort), do: nil

  defp cursor_select(select, sort) do
    Enum.uniq(select ++ Keyword.values(sort))
  end

  defp normalized_page(config, page) do
    page
    |> apply_default_page_size(Map.get(config, :default_page_size, 100))
    |> enforce_max_page_size!(Map.get(config, :max_page_size, 100))
    |> validate_page_mode!()
  end

  defp validate_page_mode!(%{after: after_cursor, number: number})
       when not is_nil(after_cursor) and not is_nil(number) do
    raise ArgumentError, "page[after] cannot be combined with page[number]"
  end

  defp validate_page_mode!(%{size: 0}) do
    raise ArgumentError, "page size must be positive for paged reads"
  end

  defp validate_page_mode!(page), do: page

  defp cursor_supported?(model, sort) do
    Cursor.configured?() and
      Enum.all?(sort, fn {direction, field} ->
        direction in [:asc, :desc] and not is_nil(Map.get(model, field))
      end)
  end

  defp lookahead_page(%{size: size} = page) when is_integer(size) do
    page
    |> Map.put(:offset_size, size)
    |> Map.put(:size, size + 1)
  end

  defp lookahead_page(page), do: page

  defp trim_lookahead(results, size) when is_integer(size),
    do: {Enum.take(results, size), length(results) > size}

  defp trim_lookahead(results, _size), do: {results, false}

  defp next_cursor([], _has_more?, _sort), do: nil
  defp next_cursor(_entries, false, _sort), do: nil

  defp next_cursor(entries, true, sort) do
    model = List.last(entries)

    if cursor_supported?(model, sort) do
      Cursor.encode(sort, model)
    end
  end

  defp apply_cursor(query, page, _sort, _schema) when not is_map_key(page, :after), do: query
  defp apply_cursor(query, %{after: nil}, _sort, _schema), do: query

  defp apply_cursor(query, %{after: cursor}, sort, schema) when is_binary(cursor) do
    values = Cursor.decode!(cursor, sort, schema)
    where(query, ^cursor_dynamic(sort, values))
  end

  defp cursor_dynamic(sort, values) do
    sort
    |> Enum.zip(values)
    |> cursor_dynamic(dynamic(false), dynamic(true))
  end

  defp cursor_dynamic([], result, _equal), do: result

  defp cursor_dynamic([{{direction, field}, value} | rest], result, equal) do
    if is_nil(value) or direction in [:asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last] do
      raise ArgumentError, "page[after] does not support nullable sort values or explicit null ordering"
    end

    comparison =
      if direction == :desc,
        do: dynamic([root: row], field(row, ^field) < ^value),
        else: dynamic([root: row], field(row, ^field) > ^value)

    result = dynamic(^result or (^equal and ^comparison))
    equal = dynamic([root: row], ^equal and field(row, ^field) == ^value)
    cursor_dynamic(rest, result, equal)
  end

  defp apply_sort(query, sort) do
    Enum.reduce(sort, query, fn {dir, column}, query ->
      order_by(query, [root: row], [{^dir, field(row, ^column)}])
    end)
  end

  defp apply_offset(query, %{after: after_cursor}) when not is_nil(after_cursor), do: query
  defp apply_offset(query, page) when not is_map_key(page, :number), do: query
  defp apply_offset(query, %{number: nil}), do: query
  defp apply_offset(query, %{number: 1}), do: query

  defp apply_offset(query, %{number: number, size: size} = page)
       when is_integer(number) and number > 1 and is_integer(size) and size >= 0 do
    offset_size = Map.get(page, :offset_size, size)
    offset(query, ^((number - 1) * offset_size))
  end

  defp apply_offset(_query, %{number: number}) do
    raise ArgumentError, "page number must be a positive integer, got: #{inspect(number)}"
  end

  defp apply_limit(query, %{size: nil}), do: query

  defp apply_limit(query, %{size: size}) when is_integer(size) and size >= 0 do
    limit(query, ^size)
  end

  defp apply_limit(_query, %{size: size}) do
    raise ArgumentError, "page size must be a non-negative integer, got: #{inspect(size)}"
  end
end

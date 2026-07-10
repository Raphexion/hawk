defmodule Hawk.Reader do
  @moduledoc """
  Small runtime for resource reader modules.

  This module handles the common read flow: option normalization, policy/caller
  filter composition, key validation, direct-field filter compilation, default
  sorting, limit application, and repo calls.
  """

  import Ecto.Query

  alias Hawk.Filter
  alias Hawk.Reader.FilterCompiler
  alias Hawk.Reader.JoinPlan
  alias Hawk.Reader.Preloader

  @allowed_options MapSet.new([:authority, :context, :filter, :page, :preloads])
  @sort_dirs [:asc, :desc, :asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last]

  @type config :: %{
          required(:repo) => module(),
          required(:schema) => module(),
          required(:filter_keys) => Enumerable.t(),
          required(:read_filter) => (term() -> Filter.t()),
          optional(:filter_handlers) => FilterCompiler.handlers(),
          optional(:join_plan) => [JoinPlan.rule()],
          optional(:forced_filter) => Filter.t(),
          optional(:preload_keys) => Enumerable.t(),
          optional(:preload_readers) => %{optional(atom()) => module()},
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
      Map.get(config, :preload_readers, %{})
    )
  end

  @doc """
  Fetches exactly one record, returning `:not_found` when none exists.
  """
  @spec one(config(), keyword() | map()) :: {:ok, struct()} | :not_found
  def one(config, opts) do
    case all(config, opts) do
      [model] -> {:ok, model}
      [] -> :not_found
      results -> raise "expected one result, got #{length(results)}"
    end
  end

  @doc """
  Fetches exactly one record or raises when no record exists.
  """
  @spec one!(config(), keyword() | map()) :: struct()
  def one!(config, opts) do
    case one(config, opts) do
      {:ok, model} -> model
      :not_found -> raise "expected one result, got none"
    end
  end

  @doc """
  Builds the query for a reader call.
  """
  @spec build_query(config(), keyword() | map()) :: Ecto.Query.t()
  def build_query(config, opts) do
    opts = normalize_options(opts)
    authority = Map.fetch!(opts, :authority)
    caller_filter = Map.fetch!(opts, :filter)
    page = Map.fetch!(opts, :page)
    page = apply_default_page_size(page, Map.get(config, :default_page_size, 100))
    page = enforce_max_page_size!(page, Map.get(config, :max_page_size, 100))

    sort = sort_order(config, page)
    validate_sort_keys!(config, sort)

    config.schema
    |> from(as: :root)
    |> apply_authorized_filter(config, authority, caller_filter, sort_columns(sort))
    |> apply_sort(sort)
    |> apply_offset(page)
    |> apply_limit(page)
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

    query
    |> JoinPlan.apply(Map.get(config, :join_plan, []), filter, sort_key)
    |> FilterCompiler.compile(config.schema, filter, Map.get(config, :filter_handlers, %{}))
  end

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
      filter: Map.get(opts, :filter, :all),
      page: normalize_page(Map.get(opts, :page, %{})),
      preloads: Map.get(opts, :preloads, [])
    }
  end

  defp normalize_page(page) when is_map(page) do
    dir = Map.get(page, :dir, :asc)

    unless dir in @sort_dirs do
      raise ArgumentError, "invalid sort direction #{inspect(dir)}"
    end

    %{
      column: Map.get(page, :column),
      dir: dir,
      size: Map.get(page, :size),
      number: Map.get(page, :number),
      cursor: Map.get(page, :cursor)
    }
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

  defp sort_order(_config, %{column: column, dir: dir})
       when is_atom(column) and not is_nil(column), do: [{dir, column}]

  defp sort_order(config, %{column: nil}) do
    case Map.get(config, :default_sort, asc: :id) do
      [] -> [asc: :id]
      sort -> sort
    end
  end

  defp sort_columns(sort), do: Keyword.values(sort)

  defp apply_sort(query, sort) do
    Enum.reduce(sort, query, fn {dir, column}, query ->
      order_by(query, [root: row], [{^dir, field(row, ^column)}])
    end)
  end

  defp apply_offset(query, %{number: nil}), do: query
  defp apply_offset(query, %{number: 1}), do: query

  defp apply_offset(query, %{number: number, size: size})
       when is_integer(number) and number > 1 and is_integer(size) and size >= 0 do
    offset(query, ^((number - 1) * size))
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

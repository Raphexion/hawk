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

  @allowed_options MapSet.new([:authority, :filter, :page, :preloads])
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
          optional(:sort_keys) => Enumerable.t()
        }

  @doc """
  Fetches all records for a reader config and options.
  """
  @spec all(config(), keyword() | map()) :: [struct()]
  def all(config, opts) do
    opts = normalize_options(opts)

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

    validate_sort_key!(config, page.column)

    config.schema
    |> from(as: :root)
    |> apply_authorized_filter(config, authority, caller_filter, page.column)
    |> apply_sort(page)
    |> apply_limit(page)
  end

  @doc """
  Applies a reader's policy/filter/join declarations to an existing query.

  This is used for policy-aware preloads where the associated resource reader
  owns the joins and custom filter handlers needed to enforce visibility.
  """
  @spec apply_authorized_filter(Ecto.Query.t(), config(), term(), Filter.t(), atom()) ::
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
      column: Map.get(page, :column, :id),
      dir: dir,
      size: Map.get(page, :size),
      cursor: Map.get(page, :cursor)
    }
  end

  defp validate_sort_key!(config, column) do
    sort_keys =
      config
      |> Map.get(:sort_keys, [:id])
      |> Enum.to_list()
      |> case do
        [] -> [:id]
        keys -> keys
      end

    unless column in sort_keys do
      raise ArgumentError, "unsupported sort column #{inspect(column)}"
    end
  end

  defp apply_sort(query, %{column: column, dir: dir}) do
    order_by(query, [root: row], [{^dir, field(row, ^column)}])
  end

  defp apply_limit(query, %{size: nil}), do: query

  defp apply_limit(query, %{size: size}) when is_integer(size) and size >= 0 do
    limit(query, ^size)
  end

  defp apply_limit(_query, %{size: size}) do
    raise ArgumentError, "page size must be a non-negative integer, got: #{inspect(size)}"
  end
end

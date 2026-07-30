defmodule Hawk.LiveView.IndexState do
  @moduledoc false

  @type t :: %{
          required(:filter) => Hawk.Filter.t(),
          required(:page) => map(),
          required(:sort) => keyword(),
          required(:stream_reset?) => true
        }

  @spec normalize(map(), map(), t() | nil) :: t()
  def normalize(params, live_view, current \\ nil) when is_map(params) and is_map(live_view) do
    initial? = is_nil(current)
    current = current || %{filter: :all, page: %{}, sort: [], stream_reset?: true}

    filters = parse_filters(Map.get(params, "filter"), live_view)
    searches = parse_searches(Map.get(params, "search"), live_view)
    filter = merge_filter(current.filter, filters, searches, params)

    sort = parse_sort(Map.get(params, "sort"), live_view, current.sort)
    page = Map.merge(current.page, parse_page(Map.get(params, "page")))
    page = reset_page_on_query_change(page, current, filter, sort, initial?)

    %{filter: filter, page: page, sort: sort, stream_reset?: true}
  end

  defp merge_filter(current_filter, filters, searches, params) do
    filter = if Map.has_key?(params, "filter"), do: filters, else: current_filter

    if Map.has_key?(params, "search") do
      filter
      |> remove_search_keys(params["search"])
      |> merge_filter_maps(searches)
    else
      filter
    end
  end

  defp merge_filter_maps(:all, :all), do: :all
  defp merge_filter_maps(:all, right), do: right
  defp merge_filter_maps(left, :all), do: left
  defp merge_filter_maps(left, right), do: Map.merge(left, right)

  defp reset_page_on_query_change(page, _current, _filter, _sort, true), do: page

  defp reset_page_on_query_change(page, current, filter, sort, false) do
    current_query = %{sort: current.sort, filter: current.filter}
    next_query = %{sort: sort, filter: filter}

    if current_query == next_query do
      page
    else
      Map.put(page, :number, 1)
    end
  end

  defp remove_search_keys(filter, search) when is_map(filter) and is_map(search) do
    search
    |> Map.keys()
    |> Enum.reduce(filter, fn key, acc -> Map.delete(acc, String.to_existing_atom(key)) end)
    |> empty_to_all()
  end

  defp remove_search_keys(filter, _search), do: filter

  defp parse_filters(nil, _live_view), do: :all
  defp parse_filters(filter, _live_view) when filter in [%{}, ""], do: :all

  defp parse_filters(filter, live_view) when is_map(filter) do
    allowed = live_view |> index_value(:filters, []) |> atoms_by_name()

    Map.new(filter, fn {name, value} ->
      case Map.fetch(allowed, name) do
        {:ok, key} -> {key, parse_filter_value(value)}
        :error -> raise ArgumentError, "unknown LiveView filter #{inspect(name)}"
      end
    end)
  end

  defp parse_filters(_filter, _live_view),
    do: raise(ArgumentError, "LiveView filter params must be an object")

  defp parse_searches(nil, _live_view), do: :all
  defp parse_searches(search, _live_view) when search in [%{}, ""], do: :all

  defp parse_searches(search, live_view) when is_map(search) do
    searches = live_view |> index_value(:searches, []) |> Map.new(&{to_string(&1.name), &1})

    search
    |> Enum.reduce(%{}, fn {name, value}, acc ->
      case Map.fetch(searches, name) do
        {:ok, metadata} -> put_search(acc, metadata, value)
        :error -> raise ArgumentError, "unknown LiveView search #{inspect(name)}"
      end
    end)
    |> empty_to_all()
  end

  defp parse_searches(_search, _live_view),
    do: raise(ArgumentError, "LiveView search params must be an object")

  defp put_search(acc, _metadata, value) when value in [nil, ""], do: acc

  defp put_search(acc, %{name: name, operator: :ilike}, value) when is_binary(value) do
    Map.put(acc, name, {:ilike, "%#{value}%"})
  end

  defp put_search(acc, %{name: name, operator: :eq}, value), do: Map.put(acc, name, value)

  defp put_search(_acc, metadata, _value) do
    raise ArgumentError, "unsupported LiveView search operator #{inspect(metadata.operator)}"
  end

  defp parse_sort(nil, _live_view, current), do: current
  defp parse_sort("", _live_view, current), do: current

  defp parse_sort("-" <> name, live_view, _current), do: parse_sort_name(name, :desc, live_view)

  defp parse_sort(name, live_view, _current) when is_binary(name),
    do: parse_sort_name(name, :asc, live_view)

  defp parse_sort(_sort, _live_view, _current),
    do: raise(ArgumentError, "LiveView sort must be a string")

  defp parse_sort_name(name, dir, live_view) do
    allowed = live_view |> index_value(:sorts, []) |> atoms_by_name()

    case Map.fetch(allowed, name) do
      {:ok, column} -> [{dir, column}]
      :error -> raise ArgumentError, "unknown LiveView sort #{inspect(name)}"
    end
  end

  defp parse_page(nil), do: %{}
  defp parse_page(page) when page in [%{}, ""], do: %{}

  defp parse_page(page) when is_map(page) do
    %{}
    |> put_page_value(:number, Map.get(page, "number"))
    |> put_page_value(:size, Map.get(page, "size"))
  end

  defp parse_page(_page), do: raise(ArgumentError, "LiveView page params must be an object")

  defp put_page_value(page, _key, nil), do: page
  defp put_page_value(page, _key, ""), do: page
  defp put_page_value(page, key, value) when is_integer(value), do: Map.put(page, key, value)

  defp put_page_value(page, key, value) when is_binary(value),
    do: Map.put(page, key, String.to_integer(value))

  defp parse_filter_value(%{} = value) when map_size(value) == 1 do
    [{operator, operand}] = Map.to_list(value)
    {parse_filter_operator!(operator), operand}
  end

  defp parse_filter_value(value), do: value

  defp parse_filter_operator!(operator) when is_atom(operator), do: operator

  defp parse_filter_operator!(operator)
       when operator in ["eq", "neq", "in", "not_in", "lt", "lte", "gt", "gte", "like", "ilike"] do
    String.to_existing_atom(operator)
  end

  defp parse_filter_operator!(operator),
    do: raise(ArgumentError, "unsupported LiveView filter operator #{inspect(operator)}")

  defp index_value(live_view, key, default),
    do: live_view |> Map.get(:index, %{}) |> Map.get(key, default)

  defp atoms_by_name(atoms), do: Map.new(atoms, &{to_string(&1), &1})
  defp empty_to_all(map) when map == %{}, do: :all
  defp empty_to_all(map), do: map
end

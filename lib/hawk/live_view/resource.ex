defmodule Hawk.LiveView.Resource do
  @moduledoc """
  LiveView adapter contract DSL for Hawk resources.

  This module describes the LiveView-facing resource contract: assign names,
  index table metadata, show fields, and allowed UI filters. It owns data
  plumbing shape; templates still own markup and styling.
  """

  defmacro __using__(_opts) do
    quote do
      import Hawk.LiveView.Resource,
        only: [
          as: 1,
          plural_as: 1,
          index: 1,
          show: 1
        ]

      @before_compile Hawk.LiveView.Resource
    end
  end

  defmacro as(name) when is_atom(name) do
    quote do
      @hawk_live_view_as unquote(name)
    end
  end

  defmacro plural_as(name) when is_atom(name) do
    quote do
      @hawk_live_view_plural_as unquote(name)
    end
  end

  defmacro index(do: block) do
    contract = parse_index(block, __CALLER__)

    quote do
      @hawk_live_view_index unquote(Macro.escape(contract))
    end
  end

  defmacro show(do: block) do
    contract = parse_show(block, __CALLER__)

    quote do
      @hawk_live_view_show unquote(Macro.escape(contract))
    end
  end

  defmacro __before_compile__(env) do
    metadata = %{
      index: Module.get_attribute(env.module, :hawk_live_view_index) || %{},
      show: Module.get_attribute(env.module, :hawk_live_view_show) || %{}
    }

    metadata = put_optional(metadata, :as, Module.get_attribute(env.module, :hawk_live_view_as))

    metadata =
      put_optional(
        metadata,
        :plural_as,
        Module.get_attribute(env.module, :hawk_live_view_plural_as)
      )

    quote do
      def __hawk_live_view__, do: unquote(Macro.escape(metadata))
    end
  end

  defp parse_index(block, caller) do
    block
    |> expressions()
    |> Enum.reduce(
      %{filters: [], searches: [], sorts: []},
      &parse_index_expression(&1, &2, caller)
    )
    |> drop_empty(:filters)
    |> drop_empty(:searches)
    |> drop_empty(:sorts)
  end

  defp parse_show(block, caller) do
    block
    |> expressions()
    |> Enum.reduce(%{fields: []}, &parse_show_expression(&1, &2, caller))
    |> drop_empty(:fields)
  end

  defp parse_index_expression({:doc, _meta, [doc]}, acc, caller) do
    Map.put(acc, :doc, literal!(doc, caller))
  end

  defp parse_index_expression({:filter, _meta, [name]}, acc, caller) do
    Map.update!(acc, :filters, &[literal!(name, caller) | &1])
  end

  defp parse_index_expression({:search, _meta, [name]}, acc, caller) do
    Map.update!(acc, :searches, &[%{name: literal!(name, caller), operator: :ilike} | &1])
  end

  defp parse_index_expression({:search, _meta, [name, opts]}, acc, caller) when is_list(opts) do
    metadata = %{
      name: literal!(name, caller),
      operator: literal!(Keyword.get(opts, :operator, :ilike), caller)
    }

    Map.update!(acc, :searches, &[metadata | &1])
  end

  defp parse_index_expression({:sort, _meta, [name]}, acc, caller) do
    Map.update!(acc, :sorts, &[literal!(name, caller) | &1])
  end

  defp parse_index_expression({:table, _meta, [[do: block]]}, acc, caller) do
    Map.put(acc, :table, parse_table(block, caller))
  end

  defp parse_show_expression({:field, _meta, [name]}, acc, caller) do
    Map.update!(acc, :fields, &[field_metadata(name, [], caller) | &1])
  end

  defp parse_show_expression({:field, _meta, [name, opts]}, acc, caller) when is_list(opts) do
    Map.update!(acc, :fields, &[field_metadata(name, opts, caller) | &1])
  end

  defp parse_table(block, caller) do
    block
    |> expressions()
    |> Enum.map(fn
      {:column, _meta, [name]} -> field_metadata(name, [], caller)
      {:column, _meta, [name, opts]} when is_list(opts) -> field_metadata(name, opts, caller)
    end)
  end

  defp field_metadata(name, opts, caller) do
    opts
    |> Keyword.take([:label, :format, :source])
    |> Map.new(fn {key, value} -> {key, literal!(value, caller)} end)
    |> Map.put(:name, literal!(name, caller))
  end

  defp expressions({:__block__, _meta, expressions}), do: expressions
  defp expressions(expression), do: [expression]

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp drop_empty(map, key) do
    case Map.fetch!(map, key) do
      [] -> Map.delete(map, key)
      values -> Map.put(map, key, Enum.reverse(values))
    end
  end

  defp literal!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end
end

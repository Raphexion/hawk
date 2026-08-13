defmodule Hawk.Reader.JoinPlan do
  @moduledoc """
  Applies resource-declared reader joins based on active filter and sort keys.

  This module intentionally does not infer relationship paths. Resources own
  each join expression and Hawk only decides whether a declared join step
  should run.
  """

  alias Hawk.Filter

  @type rule :: %{
          required(:name) => atom(),
          required(:when_filter) => MapSet.t(atom()),
          required(:when_sort) => MapSet.t(atom()),
          required(:preserves_roots) => boolean(),
          required(:apply) => (Ecto.Query.t() -> Ecto.Query.t())
        }

  @spec apply(Ecto.Query.t(), [rule()], Filter.t(), atom() | [atom()]) :: Ecto.Query.t()
  @doc false
  def apply(query, rules, filter, sort_key) do
    filter = Filter.normalize(filter)
    active_keys = Filter.keys(filter)
    validate_or_safety!(rules, filter, active_keys)

    rules
    |> Enum.reduce({query, MapSet.new()}, fn rule, {query, applied_rules} ->
      apply_rule(rule, query, applied_rules, active_keys, sort_key)
    end)
    |> elem(0)
  end

  defp apply_rule(rule, query, applied_rules, active_keys, sort_key) do
    cond do
      MapSet.member?(applied_rules, rule.name) ->
        {query, applied_rules}

      triggered?(rule, active_keys, sort_key) ->
        {rule.apply.(query), MapSet.put(applied_rules, rule.name)}

      true ->
        {query, applied_rules}
    end
  end

  @doc false
  @spec trigger_keys([rule()]) :: MapSet.t(atom())
  def trigger_keys(rules) do
    rules
    |> Enum.flat_map(& &1.when_filter)
    |> MapSet.new()
  end

  defp validate_or_safety!(rules, filter, active_keys) do
    Enum.each(rules, fn rule ->
      filter_triggered? = not MapSet.disjoint?(rule.when_filter, active_keys)

      if filter_triggered? and not rule.preserves_roots and
           not requires_attach?(filter, rule.when_filter) do
        raise ArgumentError,
              "unsafe reader attach #{inspect(rule.name)} for OR filter keys " <>
                "#{inspect(or_branch_keys(filter, rule.when_filter))}; " <>
                "the attach may remove roots before the OR predicate is evaluated. " <>
                "Mark it preserves_roots: true only if the attachment keeps all root rows, " <>
                "or restructure the filter"
      end
    end)
  end

  # Whether every path that can satisfy the filter requires this attachment.
  # `:none` has no satisfying path, so it vacuously requires every attachment.
  defp requires_attach?(:all, _trigger_keys), do: false
  defp requires_attach?(:none, _trigger_keys), do: true

  defp requires_attach?({:and, left, right}, trigger_keys) do
    requires_attach?(left, trigger_keys) or requires_attach?(right, trigger_keys)
  end

  defp requires_attach?({:or, left, right}, trigger_keys) do
    requires_attach?(left, trigger_keys) and requires_attach?(right, trigger_keys)
  end

  defp requires_attach?(filter, trigger_keys) when is_map(filter) do
    filter
    |> Map.keys()
    |> MapSet.new()
    |> then(&(not MapSet.disjoint?(&1, trigger_keys)))
  end

  defp or_branch_keys(filter, trigger_keys) do
    filter
    |> collect_unsafe_or_keys(trigger_keys)
    |> case do
      nil -> []
      {left_keys, right_keys} -> [Enum.sort(left_keys), Enum.sort(right_keys)]
    end
  end

  defp collect_unsafe_or_keys({:or, left, right}, trigger_keys) do
    if requires_attach?(left, trigger_keys) == requires_attach?(right, trigger_keys) do
      collect_unsafe_or_keys(left, trigger_keys) || collect_unsafe_or_keys(right, trigger_keys)
    else
      {Filter.keys(left), Filter.keys(right)}
    end
  end

  defp collect_unsafe_or_keys({:and, left, right}, trigger_keys) do
    collect_unsafe_or_keys(left, trigger_keys) || collect_unsafe_or_keys(right, trigger_keys)
  end

  defp collect_unsafe_or_keys(_filter, _trigger_keys), do: nil

  defp triggered?(rule, active_keys, sort_key) do
    sort_keys = sort_key |> List.wrap() |> MapSet.new()

    not MapSet.disjoint?(rule.when_filter, active_keys) or
      not MapSet.disjoint?(rule.when_sort, sort_keys)
  end
end

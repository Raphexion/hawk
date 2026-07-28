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
          required(:apply) => (Ecto.Query.t() -> Ecto.Query.t())
        }

  @spec apply(Ecto.Query.t(), [rule()], Filter.t(), atom() | [atom()]) :: Ecto.Query.t()
  @doc false
  def apply(query, rules, filter, sort_key) do
    active_keys = Filter.keys(filter)

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

  defp triggered?(rule, active_keys, sort_key) do
    sort_keys = sort_key |> List.wrap() |> MapSet.new()

    not MapSet.disjoint?(rule.when_filter, active_keys) or
      not MapSet.disjoint?(rule.when_sort, sort_keys)
  end
end

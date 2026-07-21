defmodule Hawk.Policy.Assertions do
  @moduledoc """
  ExUnit helpers for testing Hawk policy read scopes.

  These helpers keep role/scope matrices compact while still asserting the exact
  read filter a policy exposes to readers.
  """

  import ExUnit.Assertions

  @doc """
  Asserts that `policy.read_filter/1` returns `expected` for `authority`.
  """
  def assert_read_filter(policy, authority, expected) when is_atom(policy) do
    assert policy.read_filter(authority) == expected
  end

  @doc """
  Asserts that a policy grants some read scope for `authority`.
  """
  def assert_read_allowed(policy, authority) when is_atom(policy) do
    refute policy.read_filter(authority) == :none
  end

  @doc """
  Asserts that a policy grants no read scope for `authority`.
  """
  def assert_read_denied(policy, authority) when is_atom(policy) do
    assert policy.read_filter(authority) == :none
  end

  @doc """
  Asserts a compact read matrix.

      assert_read_matrix(MyApp.Courses.Policy, [
        {Hawk.Authority.system(), :all},
        {Hawk.Authority.new(:teacher, 1, scopes: %{teacher_id: 1}), %{teacher_id: 1}},
        {Hawk.Authority.new(:teacher, 1), :none}
      ])
  """
  def assert_read_matrix(policy, cases) when is_atom(policy) and is_list(cases) do
    Enum.each(cases, fn {authority, expected} ->
      assert_read_filter(policy, authority, expected)
    end)
  end
end

defmodule Videdal.PolicySupport do
  @moduledoc """
  Shared policy helpers for the Videdal example application.

  Resource policy modules still own their authorization decisions. This module
  only centralizes mechanics that are identical across resources.
  """

  alias Hawk.Authority

  def unrestricted_read?(%Authority{} = authority) do
    Authority.system?(authority) or authority.role == :principal
  end

  def write_allowed?(%Authority{} = authority, allowed_roles) when is_list(allowed_roles) do
    cond do
      Authority.system?(authority) -> true
      Authority.readonly?(authority) -> false
      authority.role in allowed_roles -> true
      true -> false
    end
  end

  def scoped_filter(authority, required_scopes, extra_filter \\ %{}) do
    Enum.reduce_while(required_scopes, extra_filter, fn scope, filter ->
      case fetch_mapped_scope(authority, scope) do
        {:ok, key, value} -> {:cont, Map.put(filter, key, value)}
        :error -> {:halt, :none}
      end
    end)
  end

  defp fetch_mapped_scope(authority, {filter_key, scope_key}) do
    case Authority.fetch_scope(authority, scope_key) do
      {:ok, value} -> {:ok, filter_key, value}
      :error -> :error
    end
  end

  defp fetch_mapped_scope(authority, scope) when is_atom(scope) do
    case Authority.fetch_scope(authority, scope) do
      {:ok, value} -> {:ok, scope, value}
      :error -> :error
    end
  end
end

defmodule Hawk.Authority.Session do
  @moduledoc """
  Small helpers for carrying `Hawk.Authority` through web sessions and assigns.

  Hawk does not own application authentication. Apps resolve their current user
  however they like, then store the resulting authority with these stable keys so
  controllers and LiveViews can share the same convention.
  """

  alias Hawk.Authority

  @default_key :hawk_authority

  @doc """
  Returns Hawk's default assign/session key for authorities.
  """
  def default_key, do: @default_key

  @doc """
  Converts an authority into a session-safe map.
  """
  def dump(%Authority{} = authority) do
    %{
      "role" => authority.role,
      "identity" => authority.identity,
      "readonly?" => authority.readonly?,
      "system?" => authority.system?,
      "public?" => authority.public?,
      "scopes" => authority.scopes,
      "meta" => authority.meta
    }
  end

  @doc """
  Rebuilds an authority from `dump/1` output.
  """
  def load(%{"role" => role, "identity" => identity} = data) do
    %Authority{
      role: normalize_atom(role),
      identity: identity,
      readonly?: Map.get(data, "readonly?", false),
      system?: Map.get(data, "system?", false),
      public?: Map.get(data, "public?", false),
      scopes: normalize_atom_keys(Map.get(data, "scopes", %{})),
      meta: Map.get(data, "meta", %{})
    }
  end

  def load(%{role: role, identity: identity} = data) do
    %Authority{
      role: normalize_atom(role),
      identity: identity,
      readonly?: Map.get(data, :readonly?, false),
      system?: Map.get(data, :system?, false),
      public?: Map.get(data, :public?, false),
      scopes: normalize_atom_keys(Map.get(data, :scopes, %{})),
      meta: Map.get(data, :meta, %{})
    }
  end

  def load(nil), do: nil

  @doc """
  Stores an authority under the configured assign key on a socket/conn/map.
  """
  def assign_authority(socket_or_conn, %Authority{} = authority, key \\ @default_key) do
    assign_value(socket_or_conn, key, authority)
  end

  @doc """
  Fetches an authority from assigns or session-like maps.
  """
  def fetch_authority(source, key \\ @default_key) do
    source
    |> fetch_value(key)
    |> case do
      %Authority{} = authority -> {:ok, authority}
      nil -> :error
      dumped -> {:ok, load(dumped)}
    end
  end

  @doc """
  Fetches an authority or returns `Hawk.Authority.public()`.
  """
  def authority_or_public(source, key \\ @default_key) do
    case fetch_authority(source, key) do
      {:ok, authority} -> authority
      :error -> Authority.public()
    end
  end

  defp assign_value(%{assigns: assigns} = value, key, authority) when is_map(assigns) do
    put_in(value.assigns, Map.put(assigns, key, authority))
  end

  defp assign_value(value, key, authority) when is_map(value) do
    Map.put(value, key, authority)
  end

  defp fetch_value(%{assigns: assigns}, key) when is_map(assigns), do: Map.get(assigns, key)
  defp fetch_value(%{} = map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp normalize_atom_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_atom(key), value} end)
  end
end

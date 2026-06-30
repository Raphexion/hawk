defmodule Hawk.Authority do
  @moduledoc """
  Describes the actor and read/write constraints for a Hawk operation.

  Authorities are intentionally small data structures. Policies decide what a
  role means; this module only carries role, identity, readonly state, and
  scoped data needed to make those decisions.
  """

  @type role :: atom()
  @type identity :: term()
  @type scope_key :: atom()
  @type scopes :: %{optional(scope_key()) => term()}

  @type t :: %__MODULE__{
          role: role(),
          identity: identity(),
          readonly?: boolean(),
          system?: boolean(),
          scopes: scopes(),
          meta: map()
        }

  @enforce_keys [:role, :identity]
  defstruct [
    :role,
    :identity,
    readonly?: false,
    system?: false,
    scopes: %{},
    meta: %{}
  ]

  @doc """
  Builds an authority for an ordinary actor.
  """
  @spec new(role(), identity(), keyword()) :: t()
  def new(role, identity, opts \\ [])

  def new(role, identity, opts) when is_atom(role) do
    build(role, identity, false, opts)
  end

  def new(_role, _identity, _opts) do
    raise ArgumentError, "role must be an atom"
  end

  @doc """
  Builds a privileged system authority.
  """
  @spec system(keyword()) :: t()
  def system(opts \\ []) do
    identity = Keyword.get(opts, :identity, :system)

    build(:system, identity, true, opts)
  end

  @doc """
  Returns true when the authority is system-level.
  """
  @spec system?(t()) :: boolean()
  def system?(%__MODULE__{system?: system?}), do: system?

  @doc """
  Returns true when writes should be denied by default.
  """
  @spec readonly?(t()) :: boolean()
  def readonly?(%__MODULE__{readonly?: readonly?}), do: readonly?

  @doc """
  Returns a readonly copy of an authority.
  """
  @spec readonly(t()) :: t()
  def readonly(%__MODULE__{} = authority) do
    %{authority | readonly?: true}
  end

  @doc """
  Fetches a scoped policy value.
  """
  @spec fetch_scope(t(), scope_key()) :: {:ok, term()} | :error
  def fetch_scope(%__MODULE__{scopes: scopes}, key) when is_atom(key) do
    Map.fetch(scopes, key)
  end

  @doc """
  Gets a scoped policy value with a default.
  """
  @spec scope(t(), scope_key(), term()) :: term()
  def scope(%__MODULE__{scopes: scopes}, key, default \\ nil) when is_atom(key) do
    Map.get(scopes, key, default)
  end

  @doc """
  Returns a copy of the authority with an additional scoped value.
  """
  @spec put_scope(t(), scope_key(), term()) :: t()
  def put_scope(%__MODULE__{scopes: scopes} = authority, key, value) when is_atom(key) do
    %{authority | scopes: Map.put(scopes, key, value)}
  end

  @doc """
  Returns a deterministic key suitable for request-local policy caches.

  Metadata is intentionally excluded because it should not change read scope.
  """
  @spec cache_key(t()) :: term()
  def cache_key(%__MODULE__{} = authority) do
    {
      __MODULE__,
      authority.system?,
      authority.role,
      authority.identity,
      authority.readonly?,
      stable_map(authority.scopes)
    }
  end

  defp build(role, identity, system?, opts) when is_list(opts) do
    scopes = opts |> Keyword.get(:scopes, %{}) |> validate_map!(:scopes)
    meta = opts |> Keyword.get(:meta, %{}) |> validate_map!(:meta)

    %__MODULE__{
      role: role,
      identity: identity,
      system?: system?,
      readonly?: Keyword.get(opts, :readonly?, false),
      scopes: validate_scope_keys!(scopes),
      meta: meta
    }
  end

  defp build(_role, _identity, _system?, _opts) do
    raise ArgumentError, "authority options must be a keyword list"
  end

  defp validate_map!(value, _field) when is_map(value), do: value

  defp validate_map!(_value, field) do
    raise ArgumentError, "#{field} must be a map"
  end

  defp validate_scope_keys!(scopes) do
    Enum.each(scopes, fn
      {key, _value} when is_atom(key) ->
        :ok

      {key, _value} ->
        raise ArgumentError, "scope keys must be atoms, got: #{inspect(key)}"
    end)

    scopes
  end

  defp stable_map(map) do
    Enum.sort_by(map, fn {key, _value} -> :erlang.term_to_binary(key) end)
  end
end

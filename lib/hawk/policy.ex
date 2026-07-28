defmodule Hawk.Policy do
  @moduledoc """
  The read/write authorization DSL for a Hawk resource.

  A policy answers two questions: *who can read which rows?* (the read policy)
  and *who can mutate?* (the write policy). The DSL generates the boring cases;
  resource readers own the query joins and custom filters needed to *compile*
  a read policy into an actual Ecto filter.

  Read and write are deliberately separate: read access is per-role and can be
  scoped to columns the authority carries; write access is a flat allow-list of
  roles plus optional ownership checks.

  ## Read policy

  `read/1` declares which roles can read, and how their access is narrowed:

      read do
        role(:system, :all)
        role(:public, :all)
        role(:school_admin, scopes: [:school_id])
        role(:teacher, scopes: [:school_id, :teacher_id])
      end

    * `role(:any, :all)` — the role sees every row. `:system` and `:public`
      are the conventional special roles; `:public` is anonymous readonly
      access that still goes through this policy.
    * `role(:role, scopes: [:col, ...])` — the role only sees rows where each
      named column equals the authority's scope of the same name. The reader
      must declare a matching `filter/1` for each scoped column, enforced by
      `Hawk.ResourceContract`.
    * `role(:role, scopes: [{:external_col, :scope_key}, ...])` — map a scope to
      a different filter column.
    * `role(:role, filter: %{col: value})` — a static literal filter merged into
      the scoped filter.

  The generated `read_filter/1` returns `:all`, `:none`, or a filter map the
  reader compiles into the query.

  ## Write policy

  `write/1` declares who can create/update/delete:

      write(roles: [:school_admin])

  For simple ownership-based writes, require model/changeset fields to match
  authority scopes:

      write(roles: [:teacher], owned_by: [teacher_id: :teacher_id])

  `owned_by` pairs a model/changeset field with an authority scope; all pairs
  must match for the write to proceed. `:system` always passes; `:readonly`
  always fails. `write(:never)` disables all mutation (use this for read-only
  resources that still keep a writer for form generation, or to hard-stop).

  ## Generated functions

    * `read_filter/1` — compiles an `Hawk.Authority` into `:all`, `:none`, or a
      filter map.
    * `create?/1`, `update?/1`, `delete?/1` — take an `Hawk.MutationContext`,
      return a boolean.
    * `__hawk_policy__/0` — the raw read-role declarations, used by contract
      validation and `Hawk.Policy.Assertions`.

  ## See also

    * `Hawk.Authority` — the actor the policy decides against.
    * `Hawk.Policy.Assertions` — compact read-policy matrix tests.
    * `Hawk.MutationContext` — carries the changeset + authority for write checks.
  """

  defmacro __using__(_opts) do
    quote do
      import Hawk.Policy, only: [read: 1, role: 2, write: 1]

      Module.register_attribute(__MODULE__, :hawk_policy_read_roles, accumulate: true)
      @before_compile Hawk.Policy
    end
  end

  @doc """
  Declares the read policy: which roles can read, and how their access narrows.

  With `:all`, every role can read every row. With a `do` block, enumerate
  `role/2` entries. See the module docs for the scoping forms.
  """
  defmacro read(:all) do
    quote do
      @hawk_policy_read_roles {:_, :all}
    end
  end

  defmacro read(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Declares read access for a role, either `:all` or scoped to authority fields.

  ## Options

    * `:scopes` — a list of scope keys (atoms) or `{filter_column, scope_key}`
      pairs. Each must have a matching reader `filter/1`.
    * `:filter` — a static map merged into the compiled read filter.
  """
  defmacro role(role, :all) when is_atom(role) do
    quote do
      @hawk_policy_read_roles {unquote(role), :all}
    end
  end

  defmacro role(role, opts) when is_atom(role) and is_list(opts) do
    scopes = Keyword.get(opts, :scopes, [])
    filter = opts |> Keyword.get(:filter, %{}) |> literal_option!(__CALLER__)

    quote do
      @hawk_policy_read_roles {unquote(role), {:scoped, unquote(scopes), unquote(Macro.escape(filter))}}
    end
  end

  @doc """
  Disables all mutation for this resource.
  """
  defmacro write(:never) do
    quote do
      def create?(%Hawk.MutationContext{}), do: false
      def update?(%Hawk.MutationContext{}), do: false
      def delete?(%Hawk.MutationContext{}), do: false
    end
  end

  defmacro write(opts) when is_list(opts) do
    roles = Keyword.fetch!(opts, :roles)
    owned_by = Keyword.get(opts, :owned_by, [])

    quote do
      def create?(%Hawk.MutationContext{} = context),
        do: write_allowed?(context, unquote(owned_by))

      def update?(%Hawk.MutationContext{} = context),
        do: write_allowed?(context, unquote(owned_by))

      def delete?(%Hawk.MutationContext{} = context),
        do: write_allowed?(context, unquote(owned_by))

      defp write_allowed?(%Hawk.MutationContext{} = context, ownership) do
        authority = context.authority

        cond do
          Hawk.Authority.system?(authority) -> true
          Hawk.Authority.readonly?(authority) -> false
          authority.role in unquote(roles) -> Hawk.Policy.owned_by?(context, ownership)
          true -> false
        end
      end
    end
  end

  @doc false
  def owned_by?(_context, []), do: true

  @doc false
  def owned_by?(%Hawk.MutationContext{} = context, ownership) when is_list(ownership) do
    Enum.all?(ownership, fn {field, scope} ->
      with {:ok, scope_value} <- Hawk.Authority.fetch_scope(context.authority, scope),
           {:ok, field_value} <- mutation_field(context, field) do
        field_value == scope_value
      else
        _missing -> false
      end
    end)
  end

  defp mutation_field(%Hawk.MutationContext{} = context, field) when is_atom(field) do
    value = Ecto.Changeset.get_field(context.changeset, field)

    if is_nil(value), do: Map.fetch(context.model, field), else: {:ok, value}
  end

  defp literal_option!(value, _caller) when is_map(value), do: value

  defp literal_option!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end

  defmacro __before_compile__(env) do
    read_roles =
      env.module
      |> Module.get_attribute(:hawk_policy_read_roles)
      |> Enum.reverse()

    quote do
      def read_filter(%Hawk.Authority{} = authority) do
        Hawk.Policy.read_filter(authority, unquote(Macro.escape(read_roles)))
      end

      def __hawk_policy__ do
        %{read: unquote(Macro.escape(read_roles))}
      end
    end
  end

  @doc false
  def read_filter(%Hawk.Authority{} = authority, read_roles) when is_list(read_roles) do
    case List.keyfind(read_roles, authority.role, 0) || List.keyfind(read_roles, :_, 0) do
      {_role, :all} -> :all
      {_role, {:scoped, scopes, filter}} -> scoped_filter(authority, scopes, filter)
      nil -> :none
    end
  end

  defp scoped_filter(authority, scopes, filter) do
    Enum.reduce_while(scopes, filter, fn scope, acc ->
      case fetch_scope(authority, scope) do
        {:ok, filter_key, value} -> {:cont, Map.put(acc, filter_key, value)}
        :error -> {:halt, :none}
      end
    end)
  end

  defp fetch_scope(authority, {filter_key, scope_key}) do
    case Hawk.Authority.fetch_scope(authority, scope_key) do
      {:ok, value} -> {:ok, filter_key, value}
      :error -> :error
    end
  end

  defp fetch_scope(authority, scope) when is_atom(scope) do
    case Hawk.Authority.fetch_scope(authority, scope) do
      {:ok, value} -> {:ok, scope, value}
      :error -> :error
    end
  end
end

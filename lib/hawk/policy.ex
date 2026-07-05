defmodule Hawk.Policy do
  @moduledoc """
  Small policy DSL for common Hawk read/write authorization shapes.

  The DSL generates the boring policy cases while resource readers own the query
  joins and custom filters needed to compile those policies.
  """

  defmacro __using__(_opts) do
    quote do
      import Hawk.Policy, only: [read: 1, role: 2, write: 1]

      Module.register_attribute(__MODULE__, :hawk_policy_read_roles, accumulate: true)
      @before_compile Hawk.Policy
    end
  end

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

  defmacro role(role, :all) when is_atom(role) do
    quote do
      @hawk_policy_read_roles {unquote(role), :all}
    end
  end

  defmacro role(role, opts) when is_atom(role) and is_list(opts) do
    scopes = Keyword.get(opts, :scopes, [])
    filter = opts |> Keyword.get(:filter, %{}) |> literal_option!(__CALLER__)

    quote do
      @hawk_policy_read_roles {unquote(role),
                               {:scoped, unquote(scopes), unquote(Macro.escape(filter))}}
    end
  end

  defmacro write(:never) do
    quote do
      def create?(%Hawk.MutationContext{}), do: false
      def update?(%Hawk.MutationContext{}), do: false
      def delete?(%Hawk.MutationContext{}), do: false
    end
  end

  defmacro write(opts) when is_list(opts) do
    roles = Keyword.fetch!(opts, :roles)

    quote do
      def create?(%Hawk.MutationContext{} = context), do: write_allowed?(context.authority)
      def update?(%Hawk.MutationContext{} = context), do: write_allowed?(context.authority)
      def delete?(%Hawk.MutationContext{} = context), do: write_allowed?(context.authority)

      defp write_allowed?(%Hawk.Authority{} = authority) do
        cond do
          Hawk.Authority.system?(authority) -> true
          Hawk.Authority.readonly?(authority) -> false
          authority.role in unquote(roles) -> true
          true -> false
        end
      end
    end
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
    end
  end

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

defmodule Hawk.Model do
  @moduledoc """
  Thin schema DSL for Hawk-owned models.

  `Hawk.Model` keeps Ecto as the persistence layer, but lets a model declare
  association policy metadata at the association site. Hawk readers can then
  preload through the policy attached to the model association instead of
  repeating policy modules in reader declarations.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Hawk.Model, only: [model: 2]

      Module.register_attribute(__MODULE__, :hawk_association_policies, accumulate: true)
      @before_compile Hawk.Model
    end
  end

  defmacro model(source, do: block) do
    {rewritten_block, policies} = rewrite_schema_block(block, __CALLER__)

    policy_attrs =
      Enum.map(policies, fn {name, policy} ->
        quote do
          @hawk_association_policies {unquote(name), unquote(policy)}
        end
      end)

    quote do
      unquote_splicing(policy_attrs)

      Ecto.Schema.schema unquote(source) do
        unquote(rewritten_block)
      end
    end
  end

  defmacro __before_compile__(env) do
    policies =
      env.module
      |> Module.get_attribute(:hawk_association_policies)
      |> Enum.reverse()

    if policies == [] do
      quote do
        def __hawk_association_policy__(name) when is_atom(name), do: :error
      end
    else
      quote do
        def __hawk_association_policy__(name) when is_atom(name) do
          Map.fetch(unquote(Macro.escape(Map.new(policies))), name)
        end
      end
    end
  end

  defp rewrite_schema_block({:__block__, meta, expressions}, caller) do
    {expressions, policies} = rewrite_expressions(expressions, caller)
    {{:__block__, meta, expressions}, policies}
  end

  defp rewrite_schema_block(expression, caller) do
    {[rewritten_expression], policies} = rewrite_expressions([expression], caller)
    {rewritten_expression, policies}
  end

  defp rewrite_expressions(expressions, caller) do
    Enum.map_reduce(expressions, [], fn expression, policies ->
      rewrite_expression(expression, policies, caller)
    end)
  end

  defp rewrite_expression({kind, meta, [name, schema, opts]} = expression, policies, caller)
       when kind in [:belongs_to, :has_many] and is_list(opts) do
    case Keyword.pop(opts, :policy) do
      {nil, _ecto_opts} ->
        {expression, policies}

      {policy, ecto_opts} ->
        policy = Macro.expand(policy, caller)
        validate_policy_module!(kind, name, policy)
        {{kind, meta, [name, schema, ecto_opts]}, [{name, policy} | policies]}
    end
  end

  defp rewrite_expression(expression, policies, _caller), do: {expression, policies}

  defp validate_policy_module!(kind, name, policy) when is_atom(policy) do
    unless inspect(policy) =~ "." do
      raise ArgumentError,
            "#{kind} #{inspect(name)} policy must be a module, got: #{inspect(policy)}"
    end
  end

  defp validate_policy_module!(kind, name, policy) do
    raise ArgumentError,
          "#{kind} #{inspect(name)} policy must be a module, got: #{inspect(policy)}"
  end
end

defmodule Hawk.Writer.Resource do
  @moduledoc """
  Declarative writer DSL for Hawk resources.

  The DSL generates paired form and persistence functions from the same mutation
  pipeline so JSON:API writes and LiveView live validation cannot drift.
  """

  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)
    repo = Keyword.fetch!(opts, :repo)
    policy = Keyword.fetch!(opts, :policy)

    quote do
      import Hawk.Writer.Resource, only: [create: 1]

      @hawk_writer_model unquote(model)
      @hawk_writer_repo unquote(repo)
      @hawk_writer_policy unquote(policy)

      @before_compile Hawk.Writer.Resource
    end
  end

  defmacro create(do: block) do
    quote do
      @hawk_writer_create unquote(Macro.escape(block))
    end
  end

  defmacro __before_compile__(env) do
    create_block = Module.get_attribute(env.module, :hawk_writer_create)
    model = Module.get_attribute(env.module, :hawk_writer_model)
    repo = Module.get_attribute(env.module, :hawk_writer_repo)
    policy = Module.get_attribute(env.module, :hawk_writer_policy)

    create_context = quote_context_pipeline(:create, create_block, model, policy)

    quote do
      def change_create(attrs, authority) do
        attrs
        |> create_context(authority)
        |> Hawk.Writer.changeset()
      end

      def create(attrs, authority) do
        attrs
        |> create_context(authority)
        |> Hawk.RepositoryBoundary.insert(unquote(repo))
      end

      defp create_context(attrs, authority) do
        unquote(create_context)
      end
    end
  end

  defp quote_context_pipeline(:create, nil, _model, _policy) do
    raise ArgumentError, "Hawk writer resource requires a create block"
  end

  defp quote_context_pipeline(:create, block, model, policy) do
    steps = expressions(block)

    Enum.reduce(
      steps,
      quote(do: Hawk.MutationContext.create(%unquote(model){}, attrs, authority)),
      fn step, acc ->
        quote_step(step, acc)
      end
    )
    |> then(fn acc ->
      quote do
        unquote(acc)
        |> Hawk.MutationContext.validate_policy(&unquote(policy).create?/1)
      end
    end)
  end

  defp quote_step({:cast, _meta, [fields]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.cast(unquote(fields))
    end
  end

  defp quote_step({:validate_required, _meta, [fields]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate_required(unquote(fields))
    end
  end

  defp quote_step({:validate_required, _meta, [fields, opts]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate_required(unquote(fields), unquote(opts))
    end
  end

  defp quote_step(unsupported, _acc) do
    raise ArgumentError, "unsupported Hawk writer create step #{Macro.to_string(unsupported)}"
  end

  defp expressions({:__block__, _meta, expressions}), do: expressions
  defp expressions(expression), do: [expression]
end

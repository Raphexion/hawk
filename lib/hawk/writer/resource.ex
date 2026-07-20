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
      import Hawk.Writer.Resource, only: [create: 1, update: 1]

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

  defmacro update(do: block) do
    quote do
      @hawk_writer_update unquote(Macro.escape(block))
    end
  end

  defmacro __before_compile__(env) do
    create_block = Module.get_attribute(env.module, :hawk_writer_create)
    update_block = Module.get_attribute(env.module, :hawk_writer_update)
    model = Module.get_attribute(env.module, :hawk_writer_model)
    repo = Module.get_attribute(env.module, :hawk_writer_repo)
    policy = Module.get_attribute(env.module, :hawk_writer_policy)

    create_context = quote_context_pipeline(:create, create_block, model, policy)
    update_functions = quote_update_functions(update_block, repo, policy)

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

      unquote(update_functions)
    end
  end

  defp quote_update_functions(nil, _repo, _policy), do: []

  defp quote_update_functions(update_block, repo, policy) do
    update_context = quote_context_pipeline(:update, update_block, nil, policy)

    quote do
      def change_update(model, attrs, authority) do
        model
        |> update_context(attrs, authority)
        |> Hawk.Writer.changeset()
      end

      def update(model, attrs, authority) do
        model
        |> update_context(attrs, authority)
        |> Hawk.RepositoryBoundary.update(unquote(repo))
      end

      defp update_context(model, attrs, authority) do
        unquote(update_context)
      end
    end
  end

  defp quote_context_pipeline(:create, nil, _model, _policy) do
    raise ArgumentError, "Hawk writer resource requires a create block"
  end

  defp quote_context_pipeline(:create, block, model, policy) do
    block
    |> expressions()
    |> quote_pipeline(quote(do: Hawk.MutationContext.create(%unquote(model){}, attrs, authority)))
    |> then(fn acc ->
      quote do
        unquote(acc)
        |> Hawk.MutationContext.validate_policy(&unquote(policy).create?/1)
      end
    end)
  end

  defp quote_context_pipeline(:update, block, _model, policy) do
    block
    |> expressions()
    |> quote_pipeline(quote(do: Hawk.MutationContext.update(model, attrs, authority)))
    |> then(fn acc ->
      quote do
        unquote(acc)
        |> Hawk.MutationContext.validate_policy(&unquote(policy).update?/1)
      end
    end)
  end

  defp quote_pipeline(steps, initial) do
    Enum.reduce(steps, initial, fn step, acc ->
      quote_step(step, acc)
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

  defp quote_step({:validate, _meta, [validator]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate(unquote(validator))
    end
  end

  defp quote_step({:validate_changeset, _meta, [validator]}, acc) do
    quote do
      unquote(acc)
      |> Hawk.Writer.validate_changeset(unquote(validator))
    end
  end

  defp quote_step(unsupported, _acc) do
    raise ArgumentError, "unsupported Hawk writer step #{Macro.to_string(unsupported)}"
  end

  defp expressions({:__block__, _meta, expressions}), do: expressions
  defp expressions(expression), do: [expression]
end

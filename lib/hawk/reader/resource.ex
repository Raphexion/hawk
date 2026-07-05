defmodule Hawk.Reader.Resource do
  @moduledoc """
  Declarative reader DSL for Hawk resources.

  The DSL stores resource-owned reader declarations and generates the standard
  public reader API by delegating execution to `Hawk.Reader`.
  """

  @required_options [:repo, :schema, :policy]

  defmacro __using__(opts) do
    validate_options!(opts)

    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    policy = Keyword.fetch!(opts, :policy)
    forced_filter = Keyword.get(opts, :forced_filter, :all)

    quote do
      import Ecto.Query
      import Hawk.Reader.Resource, only: [attach: 3, filter: 1, filter: 2, preload: 1]

      @hawk_reader_repo unquote(repo)
      @hawk_reader_schema unquote(schema)
      @hawk_reader_policy unquote(policy)
      @hawk_reader_forced_filter unquote(Macro.escape(forced_filter))

      Module.register_attribute(__MODULE__, :hawk_reader_filter_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_handlers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_join_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_preload_keys, accumulate: true)

      @before_compile Hawk.Reader.Resource
    end
  end

  defmacro filter(key) when is_atom(key) do
    quote do
      @hawk_reader_filter_keys unquote(key)
    end
  end

  defmacro filter(key, do: block) when is_atom(key) do
    handler_name = :"__hawk_filter_#{key}__"

    quote do
      @hawk_reader_filter_keys unquote(key)
      @hawk_reader_filter_handlers {unquote(key), unquote(handler_name)}

      defp unquote(handler_name)(value) do
        handler = unquote(block)
        handler.(value)
      end
    end
  end

  defmacro preload(key) when is_atom(key) do
    quote do
      @hawk_reader_preload_keys unquote(key)
    end
  end

  defmacro attach(name, opts, do: block) when is_atom(name) and is_list(opts) do
    handler_name = :"__hawk_join_#{name}__"
    when_filter = Keyword.get(opts, :when_filter, [])
    when_sort = Keyword.get(opts, :when_sort, [])
    query_var = Macro.var(:query, __MODULE__)
    rewritten_block = rewrite_query_var(block, query_var)

    quote do
      @hawk_reader_join_rules {unquote(name), unquote(when_filter), unquote(when_sort),
                               unquote(handler_name)}

      defp unquote(handler_name)(unquote(query_var)) do
        unquote(rewritten_block)
      end
    end
  end

  defmacro __before_compile__(env) do
    filter_keys =
      env.module
      |> Module.get_attribute(:hawk_reader_filter_keys)
      |> Enum.reverse()

    filter_handlers =
      env.module
      |> Module.get_attribute(:hawk_reader_filter_handlers)
      |> Enum.reverse()

    join_rules =
      env.module
      |> Module.get_attribute(:hawk_reader_join_rules)
      |> Enum.reverse()

    preload_keys =
      env.module
      |> Module.get_attribute(:hawk_reader_preload_keys)
      |> Enum.reverse()

    validate_join_rules!(join_rules)
    validate_preload_keys!(preload_keys)

    handler_entries =
      Enum.map(filter_handlers, fn {key, handler_name} ->
        quote do
          {unquote(key), fn value -> unquote(handler_name)(value) end}
        end
      end)

    join_rule_entries =
      Enum.map(join_rules, fn {name, when_filter, when_sort, handler_name} ->
        quote do
          %{
            name: unquote(name),
            when_filter: MapSet.new(unquote(when_filter)),
            when_sort: MapSet.new(unquote(when_sort)),
            apply: fn query -> unquote(handler_name)(query) end
          }
        end
      end)

    quote do
      def filter_keys do
        MapSet.new(unquote(filter_keys))
      end

      def filter_handlers do
        Map.new([unquote_splicing(handler_entries)])
      end

      def join_plan do
        [unquote_splicing(join_rule_entries)]
      end

      def preload_keys do
        MapSet.new(unquote(preload_keys))
      end

      def read_filter(authority) do
        @hawk_reader_policy.read_filter(authority)
      end

      def one(opts), do: Hawk.Reader.one(config(), opts)
      def one!(opts), do: Hawk.Reader.one!(config(), opts)
      def all(opts), do: Hawk.Reader.all(config(), opts)

      defp config do
        %{
          repo: @hawk_reader_repo,
          schema: @hawk_reader_schema,
          filter_keys: filter_keys(),
          filter_handlers: filter_handlers(),
          join_plan: join_plan(),
          read_filter: &read_filter/1,
          forced_filter: @hawk_reader_forced_filter,
          preload_keys: preload_keys()
        }
      end
    end
  end

  defp validate_options!(opts) do
    Enum.each(@required_options, fn option ->
      unless Keyword.has_key?(opts, option) do
        raise ArgumentError, "missing required reader option #{inspect(option)}"
      end
    end)
  end

  defp validate_join_rules!(join_rules) do
    duplicate_names =
      join_rules
      |> Enum.map(&elem(&1, 0))
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    case duplicate_names do
      [] ->
        :ok

      [name] ->
        raise ArgumentError, "duplicate reader join alias #{inspect(name)}"

      names ->
        raise ArgumentError, "duplicate reader join aliases #{inspect(names)}"
    end
  end

  defp validate_preload_keys!(preload_keys) do
    duplicate_keys =
      preload_keys
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, _count} -> key end)

    case duplicate_keys do
      [] ->
        :ok

      [key] ->
        raise ArgumentError, "duplicate reader preload #{inspect(key)}"

      keys ->
        raise ArgumentError, "duplicate reader preloads #{inspect(keys)}"
    end
  end

  defp rewrite_query_var(ast, query_var) do
    Macro.prewalk(ast, fn
      {:query, meta, context} when is_atom(context) ->
        Macro.update_meta(query_var, fn query_meta -> Keyword.merge(query_meta, meta) end)

      other ->
        other
    end)
  end
end

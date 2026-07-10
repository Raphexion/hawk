defmodule Hawk.Reader.Resource do
  @moduledoc """
  Declarative reader DSL for Hawk resources.

  The DSL stores resource-owned reader declarations and generates the standard
  public reader API by delegating execution to `Hawk.Reader`.
  """

  @required_options [:repo, :schema]

  defmacro __using__(opts) do
    validate_options!(opts)

    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    policy = Keyword.get(opts, :policy) || convention_policy(__CALLER__.module)
    forced_filter = Keyword.get(opts, :forced_filter, :all)
    max_page_size = Keyword.get(opts, :max_page_size, 100)
    default_page_size = Keyword.get(opts, :default_page_size, max_page_size)

    quote do
      import Ecto.Query, except: [preload: 2]

      import Hawk.Reader.Resource,
        only: [attach: 3, filter: 1, filter: 2, preload: 1, preload: 2, sort: 1]

      @hawk_reader_repo unquote(repo)
      @hawk_reader_schema unquote(schema)
      @hawk_reader_policy unquote(policy)
      @hawk_reader_forced_filter unquote(Macro.escape(forced_filter))
      @hawk_reader_max_page_size unquote(max_page_size)
      @hawk_reader_default_page_size unquote(default_page_size)

      Module.register_attribute(__MODULE__, :hawk_reader_filter_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_handlers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_join_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_preload_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_preload_readers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_sort_keys, accumulate: true)

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

  defmacro sort(key) when is_atom(key) do
    quote do
      @hawk_reader_sort_keys unquote(key)
    end
  end

  defmacro preload(key) when is_atom(key) do
    quote do
      @hawk_reader_preload_keys unquote(key)
    end
  end

  defmacro preload(key, opts) when is_atom(key) and is_list(opts) do
    reader = opts |> Keyword.get(:reader) |> Macro.expand(__CALLER__)
    validate_preload_reader!(key, reader)

    quote do
      @hawk_reader_preload_keys unquote(key)
      @hawk_reader_preload_readers {unquote(key), unquote(reader)}
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
    declarations = reader_declarations(env.module)

    validate_join_rules!(declarations.join_rules)
    validate_preload_keys!(declarations.preload_keys)

    quote_reader(declarations)
  end

  defp convention_policy(reader_module) do
    reader_module
    |> Module.split()
    |> Enum.drop(-1)
    |> Kernel.++(["Policy"])
    |> Module.concat()
  end

  defp reader_declarations(module) do
    %{
      filter_keys: reversed_attribute(module, :hawk_reader_filter_keys),
      filter_handlers: reversed_attribute(module, :hawk_reader_filter_handlers),
      join_rules: reversed_attribute(module, :hawk_reader_join_rules),
      preload_keys: reversed_attribute(module, :hawk_reader_preload_keys),
      preload_readers: reversed_attribute(module, :hawk_reader_preload_readers),
      sort_keys: reversed_attribute(module, :hawk_reader_sort_keys)
    }
  end

  defp reversed_attribute(module, attribute) do
    module
    |> Module.get_attribute(attribute)
    |> Enum.reverse()
  end

  defp quote_reader(declarations) do
    [
      quote_metadata_functions(declarations),
      quote_public_reader_functions(),
      quote_config_function()
    ]
  end

  defp quote_metadata_functions(declarations) do
    handler_entries = quote_filter_handlers(declarations.filter_handlers)
    join_rule_entries = quote_join_rules(declarations.join_rules)
    preload_reader_entries = quote_preload_readers(declarations.preload_readers)
    filter_keys = declarations.filter_keys
    preload_keys = declarations.preload_keys
    sort_keys = declarations.sort_keys

    quote do
      def filter_keys, do: MapSet.new(unquote(filter_keys))
      def filter_handlers, do: Map.new([unquote_splicing(handler_entries)])
      def join_plan, do: [unquote_splicing(join_rule_entries)]
      def preload_keys, do: MapSet.new(unquote(preload_keys))
      def preload_readers, do: Map.new([unquote_splicing(preload_reader_entries)])
      def sort_keys, do: MapSet.new(unquote(sort_keys))
      def read_filter(authority), do: @hawk_reader_policy.read_filter(authority)
    end
  end

  defp quote_public_reader_functions do
    quote do
      def one(opts), do: Hawk.Reader.one(config(), opts)
      def one!(opts), do: Hawk.Reader.one!(config(), opts)
      def all(opts), do: Hawk.Reader.all(config(), opts)

      def preload_query(query, authority) do
        Hawk.Reader.apply_authorized_filter(query, config(), authority)
      end
    end
  end

  defp quote_config_function do
    quote do
      defp config do
        %{
          repo: @hawk_reader_repo,
          schema: @hawk_reader_schema,
          filter_keys: filter_keys(),
          filter_handlers: filter_handlers(),
          join_plan: join_plan(),
          read_filter: &read_filter/1,
          forced_filter: @hawk_reader_forced_filter,
          preload_keys: preload_keys(),
          preload_readers: preload_readers(),
          sort_keys: sort_keys(),
          default_page_size: @hawk_reader_default_page_size,
          max_page_size: @hawk_reader_max_page_size
        }
      end
    end
  end

  defp quote_filter_handlers(filter_handlers) do
    Enum.map(filter_handlers, fn {key, handler_name} ->
      quote do
        {unquote(key), fn value -> unquote(handler_name)(value) end}
      end
    end)
  end

  defp quote_join_rules(join_rules) do
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
  end

  defp quote_preload_readers(preload_readers) do
    Enum.map(preload_readers, fn {key, reader} ->
      quote do
        {unquote(key), unquote(reader)}
      end
    end)
  end

  defp validate_options!(opts) do
    Enum.each(@required_options, fn option ->
      unless Keyword.has_key?(opts, option) do
        raise ArgumentError, "missing required reader option #{inspect(option)}"
      end
    end)
  end

  defp validate_preload_reader!(_key, nil), do: :ok

  defp validate_preload_reader!(_key, reader) when is_atom(reader), do: :ok

  defp validate_preload_reader!(key, reader) do
    raise ArgumentError,
          "reader preload #{inspect(key)} reader must be a module, got: #{inspect(reader)}"
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

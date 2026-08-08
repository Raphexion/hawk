defmodule Hawk.Reader.Resource do
  @moduledoc """
  The declarative reader DSL for a Hawk resource: filters, sorts, preloads, and
  custom join rules.

  A reader owns the query surface of a resource — which columns a caller can
  filter or sort on, which associations can be preloaded, and how scoped reads
  compile into Ecto queries. It is the security-relevant surface: every filter
  narrows what a caller can see, so filters are declared deliberately, one line
  at a time, as the UI requires them.

  The DSL stores resource-owned declarations and generates the standard public
  reader API (`one/1`, `all/1`, `preload_query/2`, and metadata functions) by
  delegating execution to `Hawk.Reader`.

  ## Options

    * `:repo` (required) — the `Ecto.Repo` to query through.
    * `:schema` (required) — the `Hawk.Model` / `Ecto.Schema` to read.
    * `:policy` — the policy module (default: the conventional sibling
      `<Resource>.Policy`).
    * `:forced_filter` — a filter map always merged into every query (default
      `:all`, i.e. none). Use to globally narrow a reader.
    * `:default_sort` — `{dir, key}` or a list (default `[asc: :id]`).
    * `:max_page_size` — cap on requested page size (default `100`).
    * `:default_page_size` — page size when none requested (default
      `max_page_size`).

  ## DSL

    * `filter/1` — declare a filterable column (compiled by
      `Hawk.Reader.FilterCompiler`).
    * `filter/2` — declare a filter with a custom handler block.
    * `sort/1` — declare a sortable column.
    * `preload/1` — declare a preloadable association (resolved through the
      associated resource's reader and policy).
    * `preload/2` — declare a preload pointing at a specific reader module.
    * `attach/3` — declare a custom join rule used when filtering/sorting
      across an association.

  ## Example

      defmodule MyApp.Courses.Reader do
        use Hawk.Reader.Resource,
          repo: MyApp.Repo,
          schema: MyApp.Course,
          default_page_size: 100,
          max_page_size: 100

        filter(:id)
        filter(:school_id)
        filter(:teacher_id)
        sort(:id)
        sort(:title)
        preload(:teacher)
        preload(:grades)
      end

  ## Generated functions

    * `one/1`, `all/1` — read a member or collection, scoped by policy.
    * `preload_query/2` — an authorized preload query for an association.
    * `filter_keys/0`, `sort_keys/0`, `preload_keys/0`, `preload_readers/0`,
      `filter_handlers/0`, `join_plan/0` — the declared metadata.
    * `read_filter/1` — delegates to the policy.
    * `repo/0` — the configured repo.

  Nested includes (`include=grades.student`) become nested Ecto preloads where
  every layer uses that resource's own reader and policy — opening `courses`
  does not accidentally open `grades` or `students`.

  ## See also

    * `Hawk.Reader` — the execution engine.
    * `Hawk.Reader.FilterCompiler` — how `filter/1` compiles to Ecto.
    * `Hawk.Policy` — the read policy that scopes queries.
  """

  @required_options [:repo, :schema]

  @doc false
  defmacro __using__(opts) do
    validate_options!(opts)

    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    policy = Keyword.get(opts, :policy) || convention_policy(__CALLER__.module)
    forced_filter = Keyword.get(opts, :forced_filter, :all)
    default_sort = Keyword.get(opts, :default_sort, asc: :id)
    max_page_size = Keyword.get(opts, :max_page_size, 100)
    default_page_size = Keyword.get(opts, :default_page_size, max_page_size)

    quote do
      import Ecto.Query, except: [preload: 2]

      import Hawk.Reader.Resource,
        only: [attach: 3, filter: 1, filter: 2, preload: 1, preload: 2, sort: 1]

      @hawk_reader_repo unquote(repo)
      @hawk_reader_schema unquote(schema)
      @hawk_reader_policy unquote(policy)
      @hawk_reader_forced_filter unquote(forced_filter)
      @hawk_reader_default_sort unquote(default_sort)
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

  @doc """
  Declares a filterable column. Compiled by `Hawk.Reader.FilterCompiler` into
  an Ecto `where` clause keyed on the external filter name.

  Integer columns accept equality and list operators plus `:lt`, `:lte`, `:gt`,
  and `:gte`. String operands are cast to integers before compilation; invalid
  values raise `ArgumentError`.
  """
  defmacro filter(key) when is_atom(key) do
    quote do
      @hawk_reader_filter_keys unquote(key)
    end
  end

  @doc """
  Declares a filterable column with a custom handler block.

  The block must evaluate to a function of one argument (the supplied filter
  value) returning an Ecto query fragment or keyword filter.
  """
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

  @doc """
  Declares a sortable column. Both `key` and `-key` are accepted by callers.
  """
  defmacro sort(key) when is_atom(key) do
    quote do
      @hawk_reader_sort_keys unquote(key)
    end
  end

  @doc """
  Declares a preloadable association. The association is loaded through the
  associated resource's own reader and policy (see `Hawk.Reader.Resource`).
  """
  defmacro preload(key) when is_atom(key) do
    quote do
      @hawk_reader_preload_keys unquote(key)
    end
  end

  @doc """
  Declares a preloadable association resolved through a specific reader module,
  overriding the convention-based discovery.

  ## Options

    * `:reader` — the reader module to preload through.
  """
  defmacro preload(key, opts) when is_atom(key) and is_list(opts) do
    reader = opts |> Keyword.get(:reader) |> Macro.expand(__CALLER__)
    validate_preload_reader!(key, reader)

    quote do
      @hawk_reader_preload_keys unquote(key)
      @hawk_reader_preload_readers {unquote(key), unquote(reader)}
    end
  end

  @doc """
  Declares a custom join rule used when filtering or sorting across an
  association that needs an explicit join.

  ## Options

    * `:when_filter` — keys that trigger this join.
    * `:when_sort` — sort keys that trigger this join.

  The block receives the query variable and must return an Ecto query.
  """
  defmacro attach(name, opts, do: block) when is_atom(name) and is_list(opts) do
    handler_name = :"__hawk_join_#{name}__"
    when_filter = Keyword.get(opts, :when_filter, [])
    when_sort = Keyword.get(opts, :when_sort, [])
    query_var = Macro.var(:query, __MODULE__)
    rewritten_block = rewrite_query_var(block, query_var)

    quote do
      @hawk_reader_join_rules {unquote(name), unquote(when_filter), unquote(when_sort), unquote(handler_name)}

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
      def all(opts), do: Hawk.Reader.all(config(), opts)

      def preload_query(query, authority) do
        query
        |> Hawk.Reader.apply_authorized_filter(config(), authority)
        |> Hawk.Reader.apply_scope(config(), %{}, %{authority: authority})
      end
    end
  end

  defp quote_config_function do
    quote do
      @doc """
      Returns the repo module this reader is configured with.
      """
      def repo, do: @hawk_reader_repo

      defp config do
        %{
          repo: @hawk_reader_repo,
          schema: @hawk_reader_schema,
          filter_keys: filter_keys(),
          filter_handlers: filter_handlers(),
          join_plan: join_plan(),
          read_filter: &read_filter/1,
          forced_filter: @hawk_reader_forced_filter,
          default_sort: @hawk_reader_default_sort,
          preload_keys: preload_keys(),
          preload_readers: preload_readers(),
          scope: &__MODULE__.scope/3,
          sort_keys: sort_keys(),
          default_page_size: @hawk_reader_default_page_size,
          max_page_size: @hawk_reader_max_page_size
        }
      end

      unless Module.defines?(__MODULE__, {:scope, 3}) do
        def scope(query, _params, _opts), do: query
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

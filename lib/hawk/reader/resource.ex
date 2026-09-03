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
    * `filter/2` with a block — declare a filter with a custom handler.
    * `filter/3` with `value: :object` and a block — declare a custom filter
      that receives a structured object as `{:eq, object}`. Nested object keys
      remain strings.
    * `filter/2` with `type: :coordinates` — declare an indexed PostGIS
      coordinate filter with a required `:max_radius_meters`.
    * `import_filters/1` — compose a resource-specific
      `Hawk.Reader.FilterSet` into this reader.
    * `sort/1` — declare a sortable column.
    * `rank_scope/2` — declare a named internal ordering hook selected by a
      source-backed `Hawk.Query` rank.
    * `preload/1` — declare a preloadable association (resolved through the
      associated resource's reader and policy).
    * `preload/2` — declare a preload pointing at a specific reader module or
      add an explicit per-parent `:limit` for a direct `has_many` association.
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

    * `one/1`, `all/1`, `page/1` — read a member, collection, or bounded
      collection with continuation metadata, scoped by policy.
    * `preload_query/2` — an authorized preload query for an association.
    * `filter_keys/0`, `filter_value_types/0`, `coordinate_filters/0`,
      `sort_keys/0`, `rank_scope_keys/0`, `rank_scopes/0`, `preload_keys/0`,
      `preload_readers/0`, `filter_handlers/0`, `join_plan/0` — the declared
      metadata.
    * `read_filter/1` — delegates to the policy.
    * `repo/0` — the configured repo.

  Nested includes (`include=grades.student`) become nested Ecto preloads where
  every layer uses that resource's own reader and policy — opening `courses`
  does not accidentally open `grades` or `students`.

  ## See also

    * `Hawk.Reader` — the execution engine.
    * `Hawk.Reader.FilterSet` — independently testable filter groups.
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
        only: [
          attach: 3,
          filter: 1,
          filter: 2,
          filter: 3,
          import_filters: 1,
          preload: 1,
          preload: 2,
          rank_scope: 2,
          sort: 1
        ]

      @hawk_reader_repo unquote(repo)
      @hawk_reader_schema unquote(schema)
      @hawk_reader_policy unquote(policy)
      @hawk_reader_forced_filter unquote(forced_filter)
      @hawk_reader_default_sort unquote(default_sort)
      @hawk_reader_max_page_size unquote(max_page_size)
      @hawk_reader_default_page_size unquote(default_page_size)

      Module.register_attribute(__MODULE__, :hawk_reader_filter_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_handlers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_value_types, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_coordinate_filters, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_join_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_sets, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_preload_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_preload_readers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_preload_options, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_rank_scopes, accumulate: true)
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
  Declares either a custom filter handler or a PostGIS coordinate filter.

  A custom block must evaluate to a function of one argument (the supplied
  filter value) returning an Ecto query fragment or keyword filter.

  A coordinate filter uses options instead of a block. Its schema field must
  use `Geo.PostGIS.Geometry` over a database `geography(Point, 4326)` column
  with a GiST index. `:max_radius_meters` is required and bounds every `near`
  request.

      filter(:location, type: :coordinates, max_radius_meters: 100_000)
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

  defmacro filter(key, opts) when is_atom(key) and is_list(opts) do
    if Keyword.has_key?(opts, :value) do
      __object_filter_value_type__(key, opts, __CALLER__)

      raise ArgumentError,
            "object-valued filter #{inspect(key)} requires a custom handler block"
    end

    metadata = __coordinate_filter_metadata__(key, opts, __CALLER__)

    quote do
      @hawk_reader_filter_keys unquote(key)
      @hawk_reader_coordinate_filters {unquote(key), unquote(Macro.escape(metadata))}
    end
  end

  @doc """
  Declares an object-valued custom filter.

  The outer value must be an object. Hawk preserves its nested maps, lists, and
  scalar leaves, then normalizes it to `{:eq, object}` before invoking the
  handler. Nested keys remain strings and application code owns validation of
  the object's members and semantics.

      filter :score_range, value: :object do
        fn {:eq, %{"minimum" => minimum, "maximum" => maximum}} ->
          dynamic([root: row], row.score >= ^minimum and row.score <= ^maximum)
        end
      end
  """
  defmacro filter(key, opts, do: block) when is_atom(key) and is_list(opts) do
    value_type = __object_filter_value_type__(key, opts, __CALLER__)
    handler_name = :"__hawk_filter_#{key}__"

    quote do
      @hawk_reader_filter_keys unquote(key)
      @hawk_reader_filter_handlers {unquote(key), unquote(handler_name)}
      @hawk_reader_filter_value_types {unquote(key), unquote(value_type)}

      defp unquote(handler_name)(value) do
        handler = unquote(block)
        handler.(value)
      end
    end
  end

  @doc """
  Imports a resource-specific `Hawk.Reader.FilterSet`.

  Imported filter keys, handlers, coordinate metadata, and attach rules become
  part of the reader's normal metadata and query compilation. Filter sets must
  declare the same schema as the reader.
  """
  defmacro import_filters(filter_set) do
    filter_set = Macro.expand(filter_set, __CALLER__)

    unless is_atom(filter_set) do
      raise ArgumentError, "reader filter set must be a module, got: #{Macro.to_string(filter_set)}"
    end

    quote do
      @hawk_reader_filter_sets unquote(filter_set)
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
  Declares a named, internal ranking scope for source-backed queries.

  Rank scopes are not public caller sorts. They are selected by a `Hawk.Query`
  rank declaration and receive the authorized, filtered source query plus reader
  params/options before pagination is applied.
  """
  defmacro rank_scope(name, do: block) when is_atom(name) do
    handler_name = :"__hawk_rank_scope_#{name}__"
    query_var = Macro.var(:query, __MODULE__)
    params_var = Macro.var(:params, __MODULE__)
    opts_var = Macro.var(:opts, __MODULE__)

    rewritten_block =
      block
      |> rewrite_query_var(query_var)
      |> rewrite_params_var(params_var)
      |> rewrite_opts_var(opts_var)

    quote do
      @hawk_reader_rank_scopes {unquote(name), unquote(handler_name)}

      defp unquote(handler_name)(unquote(query_var), unquote(params_var), unquote(opts_var)) do
        _ = unquote(params_var)
        _ = unquote(opts_var)
        unquote(rewritten_block)
      end
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
    limit = opts |> Keyword.get(:limit) |> Macro.expand(__CALLER__)
    unknown_options = Keyword.keys(opts) -- [:reader, :limit]

    if unknown_options != [] do
      raise ArgumentError, "unknown reader preload option #{inspect(hd(unknown_options))} for #{inspect(key)}"
    end

    if reader != nil, do: validate_preload_reader!(key, reader)

    unless is_nil(limit) or (is_integer(limit) and limit > 0) do
      raise ArgumentError, "reader preload #{inspect(key)} :limit must be a positive integer"
    end

    quote do
      @hawk_reader_preload_keys unquote(key)
      unquote(if reader != nil, do: quote(do: @hawk_reader_preload_readers({unquote(key), unquote(reader)})))
      unquote(if limit != nil, do: quote(do: @hawk_reader_preload_options({unquote(key), %{limit: unquote(limit)}})))
    end
  end

  @doc """
  Declares a custom join rule used when filtering or sorting across an
  association that needs an explicit join.

  ## Options

    * `:when_filter` — keys that trigger this join.
    * `:when_sort` — sort keys that trigger this join.
    * `:preserves_roots` — whether the attachment keeps every root row available
      to the query (default `false`). Set this only for transformations such as a
      left join that cannot remove roots needed by another `OR` path.
    * `:multiplies_roots` — whether one root may become multiple SQL rows
      (default `false`). This metadata documents cardinality for pagination and
      diagnostics; root counts are always distinct for correctness.

  A triggering filter must semantically require the attachment whenever it can
  match. The block receives the query variable and must return an Ecto query.
  """
  defmacro attach(name, opts, do: block) when is_atom(name) and is_list(opts) do
    handler_name = :"__hawk_join_#{name}__"

    {when_filter, when_sort, preserves_roots, multiplies_roots} =
      __attach_options__(name, opts, __CALLER__, :reader)

    query_var = Macro.var(:query, __MODULE__)
    rewritten_block = rewrite_query_var(block, query_var)

    quote do
      @hawk_reader_join_rules {unquote(name), unquote(when_filter), unquote(when_sort), unquote(preserves_roots),
                               unquote(multiplies_roots), unquote(handler_name)}

      defp unquote(handler_name)(unquote(query_var)) do
        unquote(rewritten_block)
      end
    end
  end

  defmacro __before_compile__(env) do
    declarations = reader_declarations(env.module)
    schema = Module.get_attribute(env.module, :hawk_reader_schema)

    validate_filter_keys!(declarations.filter_keys)
    validate_join_rules!(declarations.join_rules)
    validate_preload_keys!(declarations.preload_keys)
    validate_rank_scopes!(declarations.rank_scopes)

    Hawk.Reader.FilterSet.validate_imports!(
      env.module,
      schema,
      declarations.filter_keys,
      Enum.map(declarations.join_rules, &elem(&1, 0)),
      declarations.filter_sets
    )

    quote_reader(declarations, schema)
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
      filter_value_types: reversed_attribute(module, :hawk_reader_filter_value_types),
      coordinate_filters: reversed_attribute(module, :hawk_reader_coordinate_filters),
      join_rules: reversed_attribute(module, :hawk_reader_join_rules),
      filter_sets: reversed_attribute(module, :hawk_reader_filter_sets),
      preload_keys: reversed_attribute(module, :hawk_reader_preload_keys),
      preload_readers: reversed_attribute(module, :hawk_reader_preload_readers),
      preload_options: reversed_attribute(module, :hawk_reader_preload_options),
      rank_scopes: reversed_attribute(module, :hawk_reader_rank_scopes),
      sort_keys: reversed_attribute(module, :hawk_reader_sort_keys)
    }
  end

  defp reversed_attribute(module, attribute) do
    module
    |> Module.get_attribute(attribute)
    |> Enum.reverse()
  end

  defp quote_reader(declarations, schema) do
    quote_filter_metadata_functions(declarations, schema) ++
      [
        quote_reader_metadata_functions(declarations),
        quote_public_reader_functions(),
        quote_config_function()
      ]
  end

  defp quote_filter_metadata_functions(declarations, schema) do
    handler_entries = quote_filter_handlers(declarations.filter_handlers)
    filter_value_type_entries = quote_filter_value_types(declarations.filter_value_types)
    coordinate_filter_entries = quote_coordinate_filters(declarations.coordinate_filters)
    join_rule_entries = quote_join_rules(declarations.join_rules)

    [
      quote do
        defp local_filter_declarations do
          %{
            source: __MODULE__,
            schema: unquote(schema),
            filter_keys: MapSet.new(unquote(declarations.filter_keys)),
            filter_handlers: Map.new([unquote_splicing(handler_entries)]),
            filter_value_types: Map.new([unquote_splicing(filter_value_type_entries)]),
            coordinate_filters: Map.new([unquote_splicing(coordinate_filter_entries)]),
            join_plan: [unquote_splicing(join_rule_entries)]
          }
        end
      end,
      quote do
        defp filter_declarations do
          Hawk.Reader.FilterSet.compose(
            local_filter_declarations(),
            unquote(declarations.filter_sets),
            unquote(schema)
          )
        end

        def filter_keys, do: filter_declarations().filter_keys
        def filter_handlers, do: filter_declarations().filter_handlers
        def filter_value_types, do: filter_declarations().filter_value_types
        def coordinate_filters, do: filter_declarations().coordinate_filters
        def join_plan, do: filter_declarations().join_plan
      end
    ]
  end

  defp quote_reader_metadata_functions(declarations) do
    preload_reader_entries = quote_preload_readers(declarations.preload_readers)
    preload_option_entries = quote_preload_options(declarations.preload_options)
    rank_scope_entries = quote_rank_scopes(declarations.rank_scopes)

    quote do
      def preload_keys, do: MapSet.new(unquote(declarations.preload_keys))
      def preload_readers, do: Map.new([unquote_splicing(preload_reader_entries)])
      def preload_options, do: Map.new([unquote_splicing(preload_option_entries)])
      def rank_scopes, do: Map.new([unquote_splicing(rank_scope_entries)])
      def rank_scope_keys, do: rank_scopes() |> Map.keys() |> MapSet.new()
      def sort_keys, do: MapSet.new(unquote(declarations.sort_keys))
      def read_filter(authority), do: @hawk_reader_policy.read_filter(authority)
    end
  end

  defp quote_public_reader_functions do
    quote do
      @dialyzer {:nowarn_function, one: 1, all: 1, page: 1, count: 1, preload_query: 2}

      def one(opts), do: Hawk.Reader.one(config(), opts)
      def all(opts), do: Hawk.Reader.all(config(), opts)
      def page(opts), do: Hawk.Reader.page(config(), opts)
      def count(opts), do: Hawk.Reader.count(config(), opts)

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

      def default_sort, do: @hawk_reader_default_sort
      def default_page_size, do: @hawk_reader_default_page_size
      def max_page_size, do: @hawk_reader_max_page_size

      defp config do
        filter_declarations = filter_declarations()

        %{
          repo: @hawk_reader_repo,
          schema: @hawk_reader_schema,
          identity: Hawk.JsonApi.Schema.identity(@hawk_reader_schema),
          filter_keys: filter_declarations.filter_keys,
          filter_handlers: filter_declarations.filter_handlers,
          filter_value_types: filter_declarations.filter_value_types,
          coordinate_filters: filter_declarations.coordinate_filters,
          join_plan: filter_declarations.join_plan,
          read_filter: &read_filter/1,
          forced_filter: @hawk_reader_forced_filter,
          default_sort: @hawk_reader_default_sort,
          preload_keys: preload_keys(),
          preload_readers: preload_readers(),
          preload_options: preload_options(),
          rank_scopes: rank_scopes(),
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

  defp quote_filter_value_types(filter_value_types) do
    Enum.map(filter_value_types, fn {key, value_type} ->
      quote do
        {unquote(key), unquote(value_type)}
      end
    end)
  end

  defp quote_coordinate_filters(coordinate_filters) do
    Enum.map(coordinate_filters, fn {key, metadata} ->
      quote do
        {unquote(key), unquote(Macro.escape(metadata))}
      end
    end)
  end

  defp quote_rank_scopes(rank_scopes) do
    Enum.map(rank_scopes, fn {key, handler_name} ->
      quote do
        {unquote(key), fn query, params, opts -> unquote(handler_name)(query, params, opts) end}
      end
    end)
  end

  defp quote_join_rules(join_rules) do
    Enum.map(join_rules, fn {name, when_filter, when_sort, preserves_roots, multiplies_roots, handler_name} ->
      quote do
        %{
          name: unquote(name),
          when_filter: MapSet.new(unquote(when_filter)),
          when_sort: MapSet.new(unquote(when_sort)),
          preserves_roots: unquote(preserves_roots),
          multiplies_roots: unquote(multiplies_roots),
          apply: fn query -> unquote(handler_name)(query) end
        }
      end
    end)
  end

  defp quote_preload_options(preload_options) do
    Enum.map(preload_options, fn {key, options} ->
      quote do
        {unquote(key), unquote(Macro.escape(options))}
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

  @doc false
  def __attach_options__(name, opts, caller, owner) do
    label = if owner == :filter_set, do: "filter set attach", else: "reader attach"

    unless Keyword.keyword?(opts) do
      raise ArgumentError, "#{label} #{inspect(name)} options must be a keyword list"
    end

    duplicate_options =
      opts
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.filter(fn {_option, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicate_options != [] do
      raise ArgumentError,
            "duplicate #{label} options #{inspect(duplicate_options)} for #{inspect(name)}"
    end

    if owner == :filter_set and Keyword.has_key?(opts, :when_sort) do
      raise ArgumentError,
            "filter set attach #{inspect(name)} cannot use :when_sort; sorting belongs to the reader"
    end

    allowed_options =
      if owner == :filter_set,
        do: [:when_filter, :preserves_roots, :multiplies_roots],
        else: [:when_filter, :when_sort, :preserves_roots, :multiplies_roots]

    unknown_options = Keyword.keys(opts) -- allowed_options

    if unknown_options != [] do
      [option | _rest] = Enum.uniq(unknown_options)
      raise ArgumentError, "unknown #{label} option #{inspect(option)} for #{inspect(name)}"
    end

    when_filter = opts |> Keyword.get(:when_filter, []) |> Macro.expand(caller)
    when_sort = opts |> Keyword.get(:when_sort, []) |> Macro.expand(caller)
    preserves_roots = opts |> Keyword.get(:preserves_roots, false) |> Macro.expand(caller)
    multiplies_roots = opts |> Keyword.get(:multiplies_roots, false) |> Macro.expand(caller)

    validate_attach_keys!(label, name, :when_filter, when_filter)
    validate_attach_keys!(label, name, :when_sort, when_sort)

    validate_attach_boolean!(label, name, :preserves_roots, preserves_roots)
    validate_attach_boolean!(label, name, :multiplies_roots, multiplies_roots)

    {when_filter, when_sort, preserves_roots, multiplies_roots}
  end

  defp validate_attach_boolean!(_label, _name, _option, value) when value in [true, false], do: :ok

  defp validate_attach_boolean!(label, name, option, _value) do
    raise ArgumentError, "#{label} #{inspect(name)} #{inspect(option)} must be a boolean"
  end

  defp validate_attach_keys!(label, name, option, keys) when is_list(keys) do
    unless Enum.all?(keys, &is_atom/1) do
      raise ArgumentError,
            "#{label} #{inspect(name)} #{inspect(option)} must be a list of atoms, got: #{inspect(keys)}"
    end
  end

  defp validate_attach_keys!(label, name, option, keys) do
    raise ArgumentError,
          "#{label} #{inspect(name)} #{inspect(option)} must be a list of atoms, got: #{inspect(keys)}"
  end

  @doc false
  def __object_filter_value_type__(key, opts, caller) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "custom filter #{inspect(key)} options must be a keyword list"
    end

    duplicate_options =
      opts
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.filter(fn {_option, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicate_options != [] do
      raise ArgumentError,
            "duplicate custom filter options #{inspect(duplicate_options)} for #{inspect(key)}"
    end

    unknown_options = Keyword.keys(opts) -- [:value]

    if unknown_options != [] do
      raise ArgumentError,
            "unknown custom filter options #{inspect(Enum.uniq(unknown_options))} for #{inspect(key)}"
    end

    value_type = opts |> Keyword.get(:value) |> Macro.expand(caller)

    unless value_type == :object do
      raise ArgumentError, "custom filter #{inspect(key)} value must be :object"
    end

    value_type
  end

  @doc false
  def __coordinate_filter_metadata__(key, opts, caller) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "coordinate filter #{inspect(key)} options must be a keyword list"
    end

    duplicate_options =
      opts
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.filter(fn {_option, count} -> count > 1 end)
      |> Enum.map(fn {option, _count} -> option end)

    if duplicate_options != [] do
      raise ArgumentError,
            "duplicate coordinate filter options #{inspect(Enum.sort(duplicate_options))} for #{inspect(key)}"
    end

    unknown_options = Keyword.keys(opts) -- [:type, :max_radius_meters]

    if unknown_options != [] do
      raise ArgumentError,
            "unknown coordinate filter options #{inspect(Enum.uniq(unknown_options))} for #{inspect(key)}"
    end

    type = opts |> Keyword.get(:type) |> Macro.expand(caller)

    unless type == :coordinates do
      raise ArgumentError, "filter #{inspect(key)} type must be :coordinates"
    end

    case Keyword.fetch(opts, :max_radius_meters) do
      {:ok, quoted_maximum} ->
        maximum = Macro.expand(quoted_maximum, caller)

        if is_number(maximum) and maximum > 0 do
          %{max_radius_meters: maximum}
        else
          raise ArgumentError,
                "coordinate filter #{inspect(key)} requires a positive :max_radius_meters"
        end

      _missing_or_invalid ->
        raise ArgumentError,
              "coordinate filter #{inspect(key)} requires a positive :max_radius_meters"
    end
  end

  defp validate_options!(opts) do
    Enum.each(@required_options, fn option ->
      unless Keyword.has_key?(opts, option) do
        raise ArgumentError, "missing required reader option #{inspect(option)}"
      end
    end)
  end

  defp validate_preload_reader!(_key, reader) when is_atom(reader), do: :ok

  defp validate_preload_reader!(key, reader) do
    raise ArgumentError,
          "reader preload #{inspect(key)} reader must be a module, got: #{inspect(reader)}"
  end

  defp validate_filter_keys!(filter_keys) do
    duplicate_keys =
      filter_keys
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, _count} -> key end)

    case duplicate_keys do
      [] ->
        :ok

      [key] ->
        raise ArgumentError, "duplicate reader filter #{inspect(key)}"

      keys ->
        raise ArgumentError, "duplicate reader filters #{inspect(Enum.sort(keys))}"
    end
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

  defp validate_rank_scopes!(rank_scopes) do
    duplicate_keys =
      rank_scopes
      |> Enum.map(&elem(&1, 0))
      |> Enum.frequencies()
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, _count} -> key end)

    case duplicate_keys do
      [] ->
        :ok

      [key] ->
        raise ArgumentError, "duplicate reader rank scope #{inspect(key)}"

      keys ->
        raise ArgumentError, "duplicate reader rank scopes #{inspect(keys)}"
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
    rewrite_var(ast, :query, query_var)
  end

  defp rewrite_params_var(ast, params_var) do
    rewrite_var(ast, :params, params_var)
  end

  defp rewrite_opts_var(ast, opts_var) do
    rewrite_var(ast, :opts, opts_var)
  end

  defp rewrite_var(ast, name, replacement_var) do
    Macro.prewalk(ast, fn
      {^name, meta, context} when is_atom(context) ->
        Macro.update_meta(replacement_var, fn replacement_meta -> Keyword.merge(replacement_meta, meta) end)

      other ->
        other
    end)
  end
end

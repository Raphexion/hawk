defmodule Hawk.Reader.FilterSet do
  @moduledoc """
  A resource-specific, independently testable set of reader filters.

  Filter sets group direct or custom filters with the attach rules and private
  helpers they need. A reader imports them with
  `import_filters(MyApp.Courses.StudentFilters)`. The reader still owns policy,
  sorting, pagination, preloads, and resource-wide scope.

  Filter sets declare their schema explicitly so Hawk can reject importing a
  set into the wrong reader and can compile the set independently in tests.
  Attach rules may use `:when_filter` but not `:when_sort`; sortable fields and
  sort-triggered joins remain Reader-owned. Triggered rules run before the
  boolean filter AST is compiled, so an `OR` that must retain roots without an
  attached association needs a semantics-preserving attachment such as a left
  join.

  ## Example

      defmodule MyApp.Courses.StudentFilters do
        use Hawk.Reader.FilterSet, schema: MyApp.Course

        attach :student, when_filter: [:student_name] do
          join(query, :inner, [root: course], student in assoc(course, :students), as: :student)
        end

        filter :student_name do
          fn name -> dynamic([student: student], student.name == ^name) end
        end
      end

  `apply_to/2` applies only this set to an existing query. It deliberately does
  not apply policy, pagination, preloads, or reader-level sorting:

      MyApp.Course
      |> Ecto.Query.from(as: :root)
      |> MyApp.Courses.StudentFilters.apply_to(%{student_name: "Ada"})

  The normal reader path composes all imported sets before compiling the filter
  AST, preserving boolean expressions that span multiple sets.
  """

  alias Hawk.Filter
  alias Hawk.Reader.FilterCompiler
  alias Hawk.Reader.JoinPlan

  @required_options [:schema]

  @type declarations :: %{
          required(:source) => module(),
          required(:schema) => module(),
          required(:filter_keys) => MapSet.t(atom()),
          required(:filter_handlers) => FilterCompiler.handlers(),
          required(:coordinate_filters) => %{optional(atom()) => Hawk.Reader.Coordinates.options()},
          required(:join_plan) => [JoinPlan.rule()]
        }

  @doc false
  defmacro __using__(opts) do
    validate_options!(opts)
    schema = opts |> Keyword.fetch!(:schema) |> Macro.expand(__CALLER__)

    quote do
      import Ecto.Query, except: [preload: 2]

      import Hawk.Reader.FilterSet,
        only: [attach: 3, filter: 1, filter: 2]

      @hawk_filter_set_schema unquote(schema)

      Module.register_attribute(__MODULE__, :hawk_reader_filter_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_filter_handlers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_coordinate_filters, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_reader_join_rules, accumulate: true)

      @before_compile Hawk.Reader.FilterSet
    end
  end

  @doc """
  Declares a filterable schema field.
  """
  defmacro filter(key) when is_atom(key) do
    quote do
      @hawk_reader_filter_keys unquote(key)
    end
  end

  @doc """
  Declares a custom filter handler owned by this filter set.
  """
  defmacro filter(key, do: block) when is_atom(key) do
    handler_name = :"__hawk_filter_#{key}__"

    quote do
      @hawk_reader_filter_keys unquote(key)
      @hawk_reader_filter_handlers {unquote(key), unquote(handler_name)}

      @doc false
      def unquote(handler_name)(value) do
        handler = unquote(block)
        handler.(value)
      end
    end
  end

  defmacro filter(key, opts) when is_atom(key) and is_list(opts) do
    metadata = Hawk.Reader.Resource.__coordinate_filter_metadata__(key, opts, __CALLER__)

    quote do
      @hawk_reader_filter_keys unquote(key)
      @hawk_reader_coordinate_filters {unquote(key), unquote(Macro.escape(metadata))}
    end
  end

  @doc """
  Declares a filter-triggered query attachment owned by this filter set.
  """
  defmacro attach(name, opts, do: block) when is_atom(name) and is_list(opts) do
    handler_name = :"__hawk_join_#{name}__"
    when_filter = Keyword.get(opts, :when_filter, [])
    when_sort = Keyword.get(opts, :when_sort, [])

    if when_sort != [] do
      raise ArgumentError,
            "filter set attach #{inspect(name)} cannot use :when_sort; sorting belongs to the reader"
    end

    query_var = Macro.var(:query, __MODULE__)
    rewritten_block = rewrite_query_var(block, query_var)

    quote do
      @hawk_reader_join_rules {unquote(name), unquote(when_filter), unquote(when_sort), unquote(handler_name)}

      @doc false
      def unquote(handler_name)(unquote(query_var)) do
        unquote(rewritten_block)
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    filter_keys = reversed_attribute(env.module, :hawk_reader_filter_keys)
    filter_handlers = reversed_attribute(env.module, :hawk_reader_filter_handlers)
    coordinate_filters = reversed_attribute(env.module, :hawk_reader_coordinate_filters)
    join_rules = reversed_attribute(env.module, :hawk_reader_join_rules)
    schema = Module.get_attribute(env.module, :hawk_filter_set_schema)

    validate_duplicate_filters!(filter_keys, env.module)
    validate_duplicate_joins!(Enum.map(join_rules, &elem(&1, 0)), env.module)

    handler_entries =
      Enum.map(filter_handlers, fn {key, handler_name} ->
        quote do
          {unquote(key), Function.capture(__MODULE__, unquote(handler_name), 1)}
        end
      end)

    coordinate_entries =
      Enum.map(coordinate_filters, fn {key, metadata} ->
        quote do
          {unquote(key), unquote(Macro.escape(metadata))}
        end
      end)

    join_entries =
      Enum.map(join_rules, fn {name, when_filter, when_sort, handler_name} ->
        quote do
          %{
            name: unquote(name),
            when_filter: MapSet.new(unquote(when_filter)),
            when_sort: MapSet.new(unquote(when_sort)),
            apply: Function.capture(__MODULE__, unquote(handler_name), 1)
          }
        end
      end)

    quote do
      @doc false
      def __hawk_filter_set__ do
        %{
          source: __MODULE__,
          schema: unquote(schema),
          filter_keys: MapSet.new(unquote(filter_keys)),
          filter_handlers: Map.new([unquote_splicing(handler_entries)]),
          coordinate_filters: Map.new([unquote_splicing(coordinate_entries)]),
          join_plan: [unquote_splicing(join_entries)]
        }
      end

      @doc """
      Applies this filter set to an existing query without reader policy,
      pagination, preloads, or resource-level sorting.
      """
      def apply_to(queryable, filter) do
        Hawk.Reader.FilterSet.apply_to(__hawk_filter_set__(), queryable, filter)
      end
    end
  end

  @doc false
  @spec apply_to(declarations(), Ecto.Queryable.t(), Filter.t()) :: Ecto.Query.t()
  def apply_to(declarations, queryable, filter) do
    Filter.validate_keys!(filter, declarations.filter_keys)

    queryable
    |> JoinPlan.apply(declarations.join_plan, filter, [])
    |> FilterCompiler.compile(
      declarations.schema,
      filter,
      declarations.filter_handlers,
      declarations.coordinate_filters
    )
  end

  @doc false
  @spec compose(declarations(), [module()], module()) :: declarations()
  def compose(local, filter_sets, schema) do
    imported = Enum.map(filter_sets, &filter_set_declarations!(&1, schema, :runtime))
    declarations = imported ++ [local]

    validate_composition!(declarations)

    %{
      source: local.source,
      schema: schema,
      filter_keys: union(declarations, :filter_keys),
      filter_handlers: merge_maps(declarations, :filter_handlers),
      coordinate_filters: merge_maps(declarations, :coordinate_filters),
      join_plan: Enum.flat_map(declarations, & &1.join_plan)
    }
  end

  @doc false
  def validate_imports!(reader, schema, local_filter_keys, local_join_names, filter_sets) do
    imported = Enum.map(filter_sets, &filter_set_declarations!(&1, schema, :compile))

    local = %{
      source: reader,
      schema: schema,
      filter_keys: MapSet.new(local_filter_keys),
      filter_handlers: %{},
      coordinate_filters: %{},
      join_plan:
        Enum.map(local_join_names, fn name ->
          %{name: name, when_filter: MapSet.new(), when_sort: MapSet.new(), apply: &Function.identity/1}
        end)
    }

    validate_composition!(imported ++ [local])
  end

  defp filter_set_declarations!(module, schema, mode) do
    ensure_filter_set_loaded!(module, mode)

    unless function_exported?(module, :__hawk_filter_set__, 0) do
      raise ArgumentError, "reader filter set #{inspect(module)} must use Hawk.Reader.FilterSet"
    end

    declarations = module.__hawk_filter_set__()

    unless declarations.schema == schema do
      raise ArgumentError,
            "reader filter set #{inspect(module)} uses #{inspect(declarations.schema)}, expected #{inspect(schema)}"
    end

    declarations
  end

  defp ensure_filter_set_loaded!(module, :compile) do
    case Code.ensure_compiled(module) do
      {:module, ^module} ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "reader filter set #{inspect(module)} is not available: #{inspect(reason)}"
    end
  end

  defp ensure_filter_set_loaded!(module, :runtime) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError, "reader filter set #{inspect(module)} is not available"
    end
  end

  defp validate_composition!(declarations) do
    validate_unique_entries!(declarations, :filter_keys, "reader filter", &MapSet.to_list/1)
    validate_unique_entries!(declarations, :join_plan, "reader join alias", &Enum.map(&1, fn rule -> rule.name end))
    :ok
  end

  defp validate_unique_entries!(declarations, field, label, values) do
    declarations
    |> Enum.flat_map(fn declarations ->
      Enum.map(values.(Map.fetch!(declarations, field)), &{&1, declarations.source})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.find(fn {_value, sources} -> length(sources) > 1 end)
    |> case do
      nil ->
        :ok

      {value, sources} ->
        formatted_sources = sources |> Enum.map_join(" and ", &inspect/1)
        raise ArgumentError, "duplicate #{label} #{inspect(value)} from #{formatted_sources}"
    end
  end

  defp union(declarations, field) do
    Enum.reduce(declarations, MapSet.new(), &MapSet.union(Map.fetch!(&1, field), &2))
  end

  defp merge_maps(declarations, field) do
    Enum.reduce(declarations, %{}, &Map.merge(&2, Map.fetch!(&1, field)))
  end

  defp reversed_attribute(module, attribute) do
    module
    |> Module.get_attribute(attribute)
    |> Enum.reverse()
  end

  defp validate_duplicate_filters!(filter_keys, module) do
    validate_local_duplicates!(filter_keys, module, "filter")
  end

  defp validate_duplicate_joins!(join_names, module) do
    validate_local_duplicates!(join_names, module, "join alias")
  end

  defp validate_local_duplicates!(values, module, label) do
    duplicates =
      values
      |> Enum.frequencies()
      |> Enum.filter(fn {_value, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case duplicates do
      [] -> :ok
      [value] -> raise ArgumentError, "duplicate filter set #{label} #{inspect(value)} in #{inspect(module)}"
      values -> raise ArgumentError, "duplicate filter set #{label}s #{inspect(values)} in #{inspect(module)}"
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

  defp validate_options!(opts) do
    Enum.each(@required_options, fn option ->
      unless Keyword.has_key?(opts, option) do
        raise ArgumentError, "missing required filter set option #{inspect(option)}"
      end
    end)
  end
end

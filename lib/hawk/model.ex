defmodule Hawk.Model do
  @moduledoc """
  Schema DSL for Hawk-owned models: a thin wrapper over `Ecto.Schema` that adds
  association resource metadata and an optional non-`id` identity.

  `Hawk.Model` keeps Ecto as the persistence layer. It does not own the external
  JSON:API shape — that lives in the sibling adapter (`MyApp.Courses.JsonApi`).
  What it adds on top of `Ecto.Schema`:

    * a `model/2` (and `model/3`) macro replacing `schema/2`, so Hawk can inject
      its default primary key and foreign-key type;
    * association resource metadata (`:policy`, `:reader`, `:resource` opts on
      `belongs_to`/`has_many`/`many_to_many`) declared at the association site,
      so readers preload through the *associated resource's reader* instead of
      duplicating preload query logic in policies; and
    * the `__hawk_resource__/0` convention function used by
      `Hawk.JsonApi.Schema` to discover the adapter.

  ## Primary key and identity

  By default every `Hawk.Model` gets a surrogate `:id` binary primary key with
  `autogenerate: true` and `@foreign_key_type :binary_id`. Two escapes:

    * `primary_key: false` on `model/3` drops the surrogate primary key
      entirely, for view-backed projections with no `:id` column.
    * A non-`id` identity is declared on the *facade* (`use Hawk.Resource,
      identity: :course_id`), not here — the model just needs the field to
      exist. See "ID-less and view-backed resources" in the README.

  ## Association resource metadata

  `belongs_to`/`has_many`/`many_to_many` accept `:policy`, `:reader`, and
  `:resource` opts. When omitted, the resource module is inferred by
  `Hawk.Resource.Convention` from the associated schema name (e.g.
  `MyApp.Course` → `MyApp.Courses`). Declaring them explicitly is how you point
  an association at a resource whose name does not follow the convention, or
  whose reader should be used for preloads.

  ## Example

      defmodule MyApp.Course do
        use Hawk.Model

        model "courses" do
          field(:title, :string)

          belongs_to(:school, MyApp.School)
          belongs_to(:teacher, MyApp.Teacher,
            reader: MyApp.Teachers.Reader,
            policy: MyApp.Teachers.Policy
          )
          has_many(:grades, MyApp.Grade, resource: MyApp.Grades)
        end
      end

  A view-backed projection with no surrogate key:

      defmodule MyApp.CourseGradeSummary do
        use Hawk.Model

        model "course_grade_summaries", primary_key: false do
          field(:course_id, :binary_id)
          field(:grade_count, :integer)
        end
      end

  ## Generated functions

    * `__hawk_resource__/0` — the resource module inferred for this schema, used
      for adapter discovery.
    * `__hawk_association_policy__/1` and `__hawk_association_reader__/1` —
      `{:ok, module}` / `:error` lookups of the per-association policy and
      reader declared with the `:policy` / `:reader` opts.

  ## See also

    * `Hawk.Resource` — the facade that consumes a model.
    * `Hawk.Resource.Convention` — schema-name → resource-module inference.
  """

  alias Hawk.Resource.Convention

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Hawk.Model, only: [model: 2, model: 3]

      Module.register_attribute(__MODULE__, :hawk_association_policies, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_association_readers, accumulate: true)
      @before_compile Hawk.Model
    end
  end

  @doc """
  Declares the schema source and block, with Hawk's default primary key.

  Equivalent to `model/3` with no options.
  """
  defmacro model(source, do: block) do
    do_model(source, [], block, __CALLER__)
  end

  @doc """
  Declares the schema source with options, then the field/association block.

  ## Options

    * `:primary_key` (default `true`) — when `false`, no surrogate `:id`
      primary key is generated. Use for view-backed projections; pair with a
      declared `identity:` on the facade for the JSON:API `id`.

  ## Example

      model "course_grade_summaries", primary_key: false do
        field(:course_id, :binary_id)
        field(:grade_count, :integer)
      end
  """
  defmacro model(source, opts, do: block) do
    do_model(source, opts, block, __CALLER__)
  end

  defp do_model(source, opts, block, caller) do
    primary_key? = Keyword.get(opts, :primary_key, true)

    {rewritten_block, metadata} = rewrite_schema_block(block, caller)

    primary_key_decl =
      if primary_key? do
        quote do: @primary_key {:id, :binary_id, autogenerate: true}
      else
        quote do: @primary_key false
      end

    quote do
      unquote_splicing(quote_attrs(:hawk_association_policies, metadata.policies))
      unquote_splicing(quote_attrs(:hawk_association_readers, metadata.readers))

      unquote(primary_key_decl)
      @foreign_key_type :binary_id

      Ecto.Schema.schema unquote(source) do
        unquote(rewritten_block)
      end
    end
  end

  defmacro __before_compile__(env) do
    policies = env.module |> Module.get_attribute(:hawk_association_policies) |> Enum.reverse()
    readers = env.module |> Module.get_attribute(:hawk_association_readers) |> Enum.reverse()

    resource = convention_resource(env.module)

    quote do
      def __hawk_resource__, do: unquote(resource)

      unquote(quote_fetch_function(:__hawk_association_policy__, policies))
      unquote(quote_fetch_function(:__hawk_association_reader__, readers))
    end
  end

  defp quote_attrs(attribute, values) do
    Enum.map(values, fn {name, module} ->
      quote do
        Module.put_attribute(__MODULE__, unquote(attribute), {unquote(name), unquote(module)})
      end
    end)
  end

  defp quote_fetch_function(name, values) do
    if values == [] do
      quote do
        def unquote(name)(key) when is_atom(key), do: :error
      end
    else
      quote do
        def unquote(name)(key) when is_atom(key) do
          Map.fetch(unquote(Macro.escape(Map.new(values))), key)
        end
      end
    end
  end

  defp rewrite_schema_block({:__block__, meta, expressions}, caller) do
    {expressions, metadata} = rewrite_expressions(expressions, caller)
    expressions = Enum.reject(expressions, &is_nil/1)
    {{:__block__, meta, expressions}, metadata}
  end

  defp rewrite_schema_block(expression, caller) do
    {[rewritten_expression], metadata} = rewrite_expressions([expression], caller)
    {rewritten_expression, metadata}
  end

  defp rewrite_expressions(expressions, caller) do
    Enum.map_reduce(expressions, %{policies: [], readers: []}, fn expression, metadata ->
      rewrite_expression(expression, metadata, caller)
    end)
  end

  defp rewrite_expression({kind, meta, [name, schema]}, metadata, caller)
       when kind in [:belongs_to, :has_many, :many_to_many] do
    rewrite_association(kind, meta, name, schema, [], metadata, caller)
  end

  defp rewrite_expression({kind, meta, [name, schema, opts]}, metadata, caller)
       when kind in [:belongs_to, :has_many, :many_to_many] and is_list(opts) do
    rewrite_association(kind, meta, name, schema, opts, metadata, caller)
  end

  defp rewrite_expression(expression, metadata, _caller), do: {expression, metadata}

  defp rewrite_association(kind, meta, name, schema, opts, metadata, caller) do
    {policy, opts} = Keyword.pop(opts, :policy)
    {reader, opts} = Keyword.pop(opts, :reader)
    {resource, opts} = Keyword.pop(opts, :resource)

    resource = expand_resource(resource, schema, caller)
    policy = policy || Module.concat(resource, Policy)
    reader = reader || Module.concat(resource, Reader)

    metadata = put_module_metadata(metadata, :policies, kind, name, policy, caller)
    metadata = put_module_metadata(metadata, :readers, kind, name, reader, caller)

    {{kind, meta, [name, schema, opts]}, metadata}
  end

  defp expand_resource(nil, schema, caller) do
    schema
    |> resolve_schema_module(caller)
    |> Convention.resource_module()
  end

  defp expand_resource(resource, _schema, caller), do: Macro.expand(resource, caller)

  defp resolve_schema_module({:__aliases__, _meta, parts}, _caller), do: Module.concat(parts)
  defp resolve_schema_module(module, caller), do: Macro.expand(module, caller)

  defp convention_resource(module), do: Convention.resource_module(module)

  defp put_module_metadata(metadata, field, kind, name, module, caller) do
    module = Macro.expand(module, caller)
    validate_module!(kind, name, field, module)
    Map.update!(metadata, field, &[{name, module} | &1])
  end

  defp validate_module!(kind, name, field, module) when is_atom(module) do
    unless inspect(module) =~ "." do
      raise ArgumentError,
            "#{kind} #{inspect(name)} #{field_name(field)} must be a module, got: #{inspect(module)}"
    end
  end

  defp validate_module!(kind, name, field, module) do
    raise ArgumentError,
          "#{kind} #{inspect(name)} #{field_name(field)} must be a module, got: #{inspect(module)}"
  end

  defp field_name(:policies), do: "policy"
  defp field_name(:readers), do: "reader"
end

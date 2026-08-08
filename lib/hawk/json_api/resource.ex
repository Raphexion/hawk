defmodule Hawk.JsonApi.Resource do
  @moduledoc """
  The JSON:API adapter DSL: the single source of a resource's external shape.

  A resource's sibling JSON:API adapter (`MyApp.Courses.JsonApi`) declares the
  external `type`, attributes, relationships, per-field writability, docs, and
  examples. Everything that renders the resource to the outside world — the
  JSON:API document, the OpenAPI spec, the controller contract — reads from
  this adapter through `Hawk.JsonApi.Schema.metadata/1`, so the model carries
  no JSON:API declarations.

  ## DSL

    * `type/1` — the JSON:API `type` string (e.g. `"courses"`).
    * `doc/1` — the resource description (OpenAPI schema description).
    * `tag/1`, `tag/2` — OpenAPI operation tag; `tag/2` takes a `:description`
      for the top-level tag entry.
    * `group/1` — emitted as `x-resource-group`.
    * `attribute/2` — an external attribute, with `:source`, `:writable`,
      `:creatable`, `:updatable`, `:doc`, `:example`, `:resolver`.
    * `relationship/2` — an external relationship, with `:source`, `:writable`,
      `:doc`, `:example`.
    * `visibility/1` — per-role subtractive field visibility rules.

  ## Attribute options

    * `:source` — the internal Ecto field (default: the attribute name).
    * `:writable` — boolean shortcut setting both creatable+updatable.
    * `:creatable` / `:updatable` — per-direction writability (default false).
    * `:doc` / `:example` — surfaced in OpenAPI.
    * `:resolver` — a `&fun/1` computing the attribute from the model (for
      computed/projection attributes not backed by a field).

  ## Relationship options

    * `:source` — the internal association name (default: the relationship name).
    * `:writable` / `:creatable` / `:updatable` — linkage writability.
    * `:doc` / `:example` — surfaced in OpenAPI. The `example` describes the
      `data` payload (a single identifier object for to-one, an array for
      to-many) and is nested under `data` in the emitted schema.

  ## Example

      defmodule MyApp.Courses.JsonApi do
        use Hawk.JsonApi.Resource

        type("courses")
        tag("Academics", description: "Academic resources.")
        group("Courses")
        doc("A course taught by a teacher at a school.")

        attribute(:title, writable: true, doc: "Course title.", example: "Math")
        attribute(:slug, source: :public_slug, creatable: true, updatable: false)

        relationship(:school, writable: true, doc: "The offering school.")
        relationship(:grades, doc: "Grades awarded in this course.")

        visibility do
          role(:public, hide: [:slug, :grades])
        end
      end

  ## Generated functions

    * `__hawk_json_api__/0` — the adapter metadata map consumed by
      `Hawk.JsonApi.Schema`, `Hawk.OpenApi`, and the controller.

  ## See also

    * `Hawk.JsonApi.Schema` — resolves adapter metadata (with caching).
    * `Hawk.OpenApi` — composes the OpenAPI spec from adapters.
    * `Hawk.JsonApi.Controller` — the generated controller base.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Hawk.JsonApi.Resource,
        only: [
          attribute: 2,
          doc: 1,
          visibility: 1,
          group: 1,
          relationship: 2,
          role: 2,
          tag: 1,
          tag: 2,
          type: 1
        ]

      Module.register_attribute(__MODULE__, :hawk_json_api_attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_relationships, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_creatable, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_updatable, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_field_filters, accumulate: true)
      @before_compile Hawk.JsonApi.Resource
    end
  end

  @doc """
  Declares the JSON:API `type` string for this resource.
  """
  defmacro type(type) when is_binary(type) do
    quote do
      @hawk_json_api_type unquote(type)
    end
  end

  @doc """
  Declares the resource description, used as the OpenAPI schema description.
  """
  defmacro doc(doc) when is_binary(doc) do
    quote do
      @hawk_json_api_doc unquote(doc)
    end
  end

  @doc """
  Declares the OpenAPI operation tag for this resource.

  With `tag/2`, pass `:description` to populate the top-level tag's description
  (avoiding `tag-description` lint warnings). When several resources share a
  tag name, the description from any of them wins.
  """
  defmacro tag(tag, opts \\ []) when is_binary(tag) and is_list(opts) do
    quote do
      @hawk_json_api_tag unquote(tag)

      if desc = Keyword.get(unquote(opts), :description) do
        @hawk_json_api_tag_description desc
      end
    end
  end

  @doc """
  Declares the resource group, emitted as `x-resource-group`.
  """
  defmacro group(group) when is_binary(group) do
    quote do
      @hawk_json_api_group unquote(group)
    end
  end

  @doc """
  Declares an external attribute. See the module docs for the option reference.
  """
  defmacro attribute(name, opts \\ []) when is_atom(name) and is_list(opts) do
    quote_field(:hawk_json_api_attributes, name, opts, __CALLER__)
  end

  @doc """
  Declares an external relationship. See the module docs for the option reference.
  """
  defmacro relationship(name, opts \\ []) when is_atom(name) and is_list(opts) do
    quote_field(:hawk_json_api_relationships, name, opts, __CALLER__)
  end

  @doc """
  Declares role-specific field visibility rules.

  Rules are subtractive only: every JSON:API field is visible by default, and a
  role can only remove declared attributes or relationships with `hide:`.
  """
  defmacro visibility(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Removes JSON:API fields for one role.
  """
  defmacro role(role, opts) when is_atom(role) and is_list(opts) do
    hidden = Keyword.get(opts, :hide, [])

    unless Keyword.keys(opts) == [:hide] do
      raise ArgumentError, "JSON:API visibility role #{inspect(role)} only supports :hide"
    end

    unless is_list(hidden) and Enum.all?(hidden, &is_atom/1) do
      raise ArgumentError, "JSON:API visibility role #{inspect(role)} :hide must be a list of atoms"
    end

    quote do
      @hawk_json_api_field_filters {unquote(role), unquote(hidden)}
    end
  end

  defmacro __before_compile__(env) do
    metadata = %{
      attributes: field_map(env.module, :hawk_json_api_attributes),
      relationships: field_map(env.module, :hawk_json_api_relationships),
      creatable: writable_fields(env.module, :hawk_json_api_creatable),
      updatable: writable_fields(env.module, :hawk_json_api_updatable)
    }

    metadata =
      put_optional(metadata, :type, Module.get_attribute(env.module, :hawk_json_api_type))

    metadata = put_optional(metadata, :doc, Module.get_attribute(env.module, :hawk_json_api_doc))
    metadata = put_optional(metadata, :tag, Module.get_attribute(env.module, :hawk_json_api_tag))

    metadata =
      put_optional(metadata, :tag_description, Module.get_attribute(env.module, :hawk_json_api_tag_description))

    metadata =
      put_optional(metadata, :group, Module.get_attribute(env.module, :hawk_json_api_group))

    metadata = put_optional_nonempty(metadata, :field_filters, field_filters(env.module))

    quote do
      def __hawk_json_api__, do: unquote(Macro.escape(metadata))
    end
  end

  defp quote_field(attribute, name, opts, caller) do
    metadata = field_metadata(opts, caller)
    writable = writable_metadata(name, opts)

    quote do
      Module.put_attribute(
        __MODULE__,
        unquote(attribute),
        {unquote(name), unquote(Macro.escape(metadata))}
      )

      unquote_splicing(writable)
    end
  end

  defp field_metadata(opts, caller) do
    opts
    |> Keyword.take([:doc, :example, :source, :resolver])
    |> Map.new(fn {key, value} -> {key, literal!(value, caller)} end)
  end

  defp writable_metadata(name, opts) do
    cond do
      Keyword.get(opts, :writable, false) ->
        [
          put_writable(:hawk_json_api_creatable, name),
          put_writable(:hawk_json_api_updatable, name)
        ]

      Keyword.get(opts, :creatable, false) and Keyword.get(opts, :updatable, false) ->
        [
          put_writable(:hawk_json_api_creatable, name),
          put_writable(:hawk_json_api_updatable, name)
        ]

      Keyword.get(opts, :creatable, false) ->
        [put_writable(:hawk_json_api_creatable, name)]

      Keyword.get(opts, :updatable, false) ->
        [put_writable(:hawk_json_api_updatable, name)]

      true ->
        []
    end
  end

  defp put_writable(attribute, name) do
    quote do
      Module.put_attribute(__MODULE__, unquote(attribute), unquote(name))
    end
  end

  defp field_filters(module) do
    declared_fields =
      module
      |> field_map(:hawk_json_api_attributes)
      |> Map.keys()
      |> Kernel.++(module |> field_map(:hawk_json_api_relationships) |> Map.keys())
      |> MapSet.new()

    module
    |> Module.get_attribute(:hawk_json_api_field_filters)
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn {role, except}, filters ->
      unknown = Enum.reject(except, &MapSet.member?(declared_fields, &1))

      if unknown != [] do
        raise ArgumentError,
              "JSON:API field role #{inspect(role)} excludes unknown fields #{inspect(Enum.sort(unknown))}"
      end

      Map.update(filters, role, MapSet.new(except), &MapSet.union(&1, MapSet.new(except)))
    end)
  end

  defp field_map(module, attribute) do
    module
    |> Module.get_attribute(attribute)
    |> Enum.reverse()
    |> Map.new()
  end

  defp writable_fields(module, attribute) do
    module
    |> Module.get_attribute(attribute)
    |> Enum.reverse()
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp put_optional_nonempty(map, _key, value) when value == %{}, do: map
  defp put_optional_nonempty(map, key, value), do: Map.put(map, key, value)

  defp literal!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end
end

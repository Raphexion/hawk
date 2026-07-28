defmodule Hawk.LiveView.Resource do
  @moduledoc """
  The LiveView adapter DSL: the internal-admin shape of a Hawk resource.

  Where `Hawk.JsonApi.Resource` describes the external API shape, this adapter
  describes the internal admin UI shape: assign names, the index table
  metadata (filters, searches, sorts, columns), the show screen fields, and
  the create/update form fields. It owns *data plumbing shape*; templates
  still own markup and styling.

  Every `filter`/`sort` declared here must also be declared by the resource's
  `Reader` — enforced by `Hawk.ResourceContract` — so the admin UI cannot
  expose a filter the reader does not support.

  ## DSL

    * `as/1` — the singular assign name (default: the resource name).
    * `plural_as/1` — the plural assign name.
    * `index/1` — index screen contract: `doc`, `filter`, `search`, `sort`,
      `table`.
    * `show/1` — show screen fields.
    * `create_form/1` — create form fields.
    * `update_form/1` — update form fields.
    * `gettext/1`, `dgettext/2` — mark field labels for translation.

  ## Example

      defmodule MyApp.Courses.LiveView do
        use Hawk.LiveView.Resource

        as(:course)
        plural_as(:courses)

        index do
          filter(:school_id)
          filter(:teacher_id)
          sort(:title)
          table do
            column(:title, label: "Title")
            column(:teacher, label: "Teacher")
          end
        end

        show do
          field(:title)
          field(:teacher)
        end

        create_form do
          field(:title, label: "Title")
          field(:teacher_id, label: "Teacher")
        end
      end

  ## Generated functions

    * `__hawk_live_view__/0` — the adapter metadata map consumed by
      `Hawk.LiveView` helpers and templates.

  ## See also

    * `Hawk.LiveView` — the LiveView helpers that consume this metadata.
    * `Hawk.Reader.Resource` — filters/sorts must be a subset of the reader's.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Hawk.LiveView.Resource,
        only: [
          as: 1,
          plural_as: 1,
          create_form: 1,
          dgettext: 2,
          gettext: 1,
          index: 1,
          show: 1,
          update_form: 1
        ]

      @before_compile Hawk.LiveView.Resource
    end
  end

  @doc """
  Marks a field label for translation via `gettext/1`. Returns a tagged tuple
  consumed by the LiveView label helpers.
  """
  def gettext(msgid) when is_binary(msgid), do: {:gettext, msgid}

  @doc """
  Marks a field label for translation via `dgettext/2` (domain-scoped).
  """
  def dgettext(domain, msgid) when is_binary(domain) and is_binary(msgid),
    do: {:dgettext, domain, msgid}

  @doc """
  Declares the singular assign name for the resource.
  """
  defmacro as(name) when is_atom(name) do
    quote do
      @hawk_live_view_as unquote(name)
    end
  end

  @doc """
  Declares the plural assign name for the resource.
  """
  defmacro plural_as(name) when is_atom(name) do
    quote do
      @hawk_live_view_plural_as unquote(name)
    end
  end

  @doc """
  Declares the index screen contract: filters, searches, sorts, and table
  columns. Every `filter`/`sort` must be a subset of the reader's declarations.
  """
  defmacro index(do: block) do
    contract = parse_index(block, __CALLER__)

    quote do
      @hawk_live_view_index unquote(Macro.escape(contract))
    end
  end

  @doc """
  Declares the show screen fields.
  """
  defmacro show(do: block) do
    contract = parse_show(block, __CALLER__)

    quote do
      @hawk_live_view_show unquote(Macro.escape(contract))
    end
  end

  @doc """
  Declares the create form fields, used for live validation through the writer.
  """
  defmacro create_form(do: block) do
    contract = parse_form(block, __CALLER__)

    quote do
      @hawk_live_view_create_form unquote(Macro.escape(contract))
    end
  end

  @doc """
  Declares the update form fields, used for live validation through the writer.
  """
  defmacro update_form(do: block) do
    contract = parse_form(block, __CALLER__)

    quote do
      @hawk_live_view_update_form unquote(Macro.escape(contract))
    end
  end

  defmacro __before_compile__(env) do
    metadata = %{
      index: Module.get_attribute(env.module, :hawk_live_view_index) || %{},
      show: Module.get_attribute(env.module, :hawk_live_view_show) || %{},
      create_form: Module.get_attribute(env.module, :hawk_live_view_create_form) || %{},
      update_form: Module.get_attribute(env.module, :hawk_live_view_update_form) || %{}
    }

    metadata = put_optional(metadata, :as, Module.get_attribute(env.module, :hawk_live_view_as))

    metadata =
      put_optional(
        metadata,
        :plural_as,
        Module.get_attribute(env.module, :hawk_live_view_plural_as)
      )

    quote do
      def __hawk_live_view__, do: unquote(Macro.escape(metadata))
    end
  end

  defp parse_index(block, caller) do
    block
    |> expressions()
    |> Enum.reduce(
      %{filters: [], searches: [], sorts: []},
      &parse_index_expression(&1, &2, caller)
    )
    |> drop_empty(:filters)
    |> drop_empty(:searches)
    |> drop_empty(:sorts)
  end

  defp parse_show(block, caller) do
    block
    |> expressions()
    |> Enum.reduce(%{fields: []}, &parse_show_expression(&1, &2, caller))
    |> drop_empty(:fields)
  end

  defp parse_form(block, caller) do
    block
    |> expressions()
    |> Enum.reduce(%{fields: []}, &parse_form_expression(&1, &2, caller))
    |> drop_empty(:fields)
  end

  defp parse_index_expression({:doc, _meta, [doc]}, acc, caller) do
    Map.put(acc, :doc, literal!(doc, caller))
  end

  defp parse_index_expression({:filter, _meta, [name]}, acc, caller) do
    Map.update!(acc, :filters, &[literal!(name, caller) | &1])
  end

  defp parse_index_expression({:search, _meta, [name]}, acc, caller) do
    Map.update!(acc, :searches, &[%{name: literal!(name, caller), operator: :ilike} | &1])
  end

  defp parse_index_expression({:search, _meta, [name, opts]}, acc, caller) when is_list(opts) do
    metadata = %{
      name: literal!(name, caller),
      operator: literal!(Keyword.get(opts, :operator, :ilike), caller)
    }

    Map.update!(acc, :searches, &[metadata | &1])
  end

  defp parse_index_expression({:sort, _meta, [name]}, acc, caller) do
    Map.update!(acc, :sorts, &[literal!(name, caller) | &1])
  end

  defp parse_index_expression({:table, _meta, [[do: block]]}, acc, caller) do
    Map.put(acc, :table, parse_table(block, caller))
  end

  defp parse_show_expression({:field, _meta, [name]}, acc, caller) do
    Map.update!(acc, :fields, &[field_metadata(name, [], caller) | &1])
  end

  defp parse_show_expression({:field, _meta, [name, opts]}, acc, caller) when is_list(opts) do
    Map.update!(acc, :fields, &[field_metadata(name, opts, caller) | &1])
  end

  defp parse_form_expression({:field, _meta, [name]}, acc, caller) do
    Map.update!(acc, :fields, &[field_metadata(name, [], caller) | &1])
  end

  defp parse_form_expression({:field, _meta, [name, opts]}, acc, caller) when is_list(opts) do
    Map.update!(acc, :fields, &[field_metadata(name, opts, caller) | &1])
  end

  defp parse_table(block, caller) do
    block
    |> expressions()
    |> Enum.map(fn
      {:column, _meta, [name]} -> field_metadata(name, [], caller)
      {:column, _meta, [name, opts]} when is_list(opts) -> field_metadata(name, opts, caller)
    end)
  end

  defp field_metadata(name, opts, caller) do
    opts
    |> Keyword.take([:label, :format, :source])
    |> Map.new(fn {key, value} -> {key, literal!(value, caller)} end)
    |> Map.put(:name, literal!(name, caller))
  end

  defp expressions({:__block__, _meta, expressions}), do: expressions
  defp expressions(expression), do: [expression]

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp drop_empty(map, key) do
    case Map.fetch!(map, key) do
      [] -> Map.delete(map, key)
      values -> Map.put(map, key, Enum.reverse(values))
    end
  end

  defp literal!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end
end

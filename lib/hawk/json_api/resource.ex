defmodule Hawk.JsonApi.Resource do
  @moduledoc """
  JSON:API adapter contract DSL for Hawk resources.

  This module is the adapter-specific home for external JSON:API shape: type,
  field names, docs, examples, computed/source-backed attributes, relationships,
  and create/update writability.
  """

  defmacro __using__(_opts) do
    quote do
      import Hawk.JsonApi.Resource,
        only: [
          attribute: 2,
          doc: 1,
          group: 1,
          relationship: 2,
          tag: 1,
          type: 1
        ]

      Module.register_attribute(__MODULE__, :hawk_json_api_attributes, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_relationships, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_creatable, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api_updatable, accumulate: true)
      @before_compile Hawk.JsonApi.Resource
    end
  end

  defmacro type(type) when is_binary(type) do
    quote do
      @hawk_json_api_type unquote(type)
    end
  end

  defmacro doc(doc) when is_binary(doc) do
    quote do
      @hawk_json_api_doc unquote(doc)
    end
  end

  defmacro tag(tag) when is_binary(tag) do
    quote do
      @hawk_json_api_tag unquote(tag)
    end
  end

  defmacro group(group) when is_binary(group) do
    quote do
      @hawk_json_api_group unquote(group)
    end
  end

  defmacro attribute(name, opts \\ []) when is_atom(name) and is_list(opts) do
    quote_field(:hawk_json_api_attributes, name, opts, __CALLER__)
  end

  defmacro relationship(name, opts \\ []) when is_atom(name) and is_list(opts) do
    quote_field(:hawk_json_api_relationships, name, opts, __CALLER__)
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
      put_optional(metadata, :group, Module.get_attribute(env.module, :hawk_json_api_group))

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

  defp literal!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end
end

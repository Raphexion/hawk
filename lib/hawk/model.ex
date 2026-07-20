defmodule Hawk.Model do
  @moduledoc """
  Thin schema DSL for Hawk-owned models.

  `Hawk.Model` keeps Ecto as the persistence layer, but lets a model declare
  association resource metadata at the association site. Hawk readers can then
  preload through the associated resource reader instead of duplicating preload
  query logic in policies.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Hawk.Model, only: [model: 2, json_api: 1]

      Module.register_attribute(__MODULE__, :hawk_association_policies, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_association_readers, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_json_api, accumulate: false)
      @before_compile Hawk.Model
    end
  end

  defmacro model(source, do: block) do
    {rewritten_block, metadata} = rewrite_schema_block(block, __CALLER__)

    quote do
      unquote_splicing(quote_attrs(:hawk_association_policies, metadata.policies))
      unquote_splicing(quote_attrs(:hawk_association_readers, metadata.readers))

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      Ecto.Schema.schema unquote(source) do
        unquote(rewritten_block)
      end
    end
  end

  defmacro json_api(do: block) do
    metadata = parse_json_api(block, __CALLER__)

    quote do
      @hawk_json_api unquote(Macro.escape(metadata))
    end
  end

  defmacro __before_compile__(env) do
    policies = env.module |> Module.get_attribute(:hawk_association_policies) |> Enum.reverse()
    readers = env.module |> Module.get_attribute(:hawk_association_readers) |> Enum.reverse()

    resource = convention_resource(env.module)
    json_api = Module.get_attribute(env.module, :hawk_json_api) || default_json_api(resource)

    quote do
      def __hawk_resource__, do: unquote(resource)
      def __hawk_json_api__, do: unquote(Macro.escape(json_api))

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
    Enum.map_reduce(expressions, %{policies: [], readers: [], json_api: nil}, fn expression,
                                                                                 metadata ->
      rewrite_expression(expression, metadata, caller)
    end)
  end

  defp rewrite_expression({:json_api, _meta, [[do: block]]}, metadata, caller) do
    {nil, %{metadata | json_api: parse_json_api(block, caller)}}
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

  defp parse_json_api(block, caller) do
    block
    |> block_expressions()
    |> Enum.reduce(
      %{attributes: %{}, relationships: %{}, creatable: [], updatable: []},
      fn expression, acc ->
        parse_json_api_expression(expression, acc, caller)
      end
    )
  end

  defp block_expressions({:__block__, _meta, expressions}), do: expressions
  defp block_expressions(expression), do: [expression]

  defp parse_json_api_expression({:type, _meta, [type]}, acc, caller) do
    Map.put(acc, :type, literal!(type, caller))
  end

  defp parse_json_api_expression({:doc, _meta, [doc]}, acc, caller) do
    Map.put(acc, :doc, literal!(doc, caller))
  end

  defp parse_json_api_expression({:tag, _meta, [tag]}, acc, caller) do
    Map.put(acc, :tag, literal!(tag, caller))
  end

  defp parse_json_api_expression({:group, _meta, [group]}, acc, caller) do
    Map.put(acc, :group, literal!(group, caller))
  end

  defp parse_json_api_expression({:attribute, _meta, [name, opts]}, acc, caller)
       when is_list(opts) do
    put_in(acc, [:attributes, name], field_doc(opts, caller))
  end

  defp parse_json_api_expression({:relationship, _meta, [name, opts]}, acc, caller)
       when is_list(opts) do
    put_in(acc, [:relationships, name], field_doc(opts, caller))
  end

  defp parse_json_api_expression({:attributes, _meta, [names]}, acc, caller) do
    names = literal!(names, caller)
    attributes = Map.merge(Map.new(names, &{&1, %{}}), acc.attributes)
    %{acc | attributes: attributes}
  end

  defp parse_json_api_expression({:relationships, _meta, [names]}, acc, caller) do
    names = literal!(names, caller)
    relationships = Map.merge(Map.new(names, &{&1, %{}}), acc.relationships)
    %{acc | relationships: relationships}
  end

  defp parse_json_api_expression({:creatable, _meta, [fields]}, acc, caller) do
    %{acc | creatable: literal!(fields, caller)}
  end

  defp parse_json_api_expression({:updatable, _meta, [fields]}, acc, caller) do
    %{acc | updatable: literal!(fields, caller)}
  end

  defp field_doc(opts, caller) do
    opts
    |> Keyword.take([:doc, :example, :source, :resolver])
    |> Map.new(fn {key, value} -> {key, literal!(value, caller)} end)
  end

  defp literal!(quoted, caller) do
    {value, _binding} = Code.eval_quoted(quoted, [], caller)
    value
  end

  defp default_json_api(resource) do
    %{
      type: resource |> Module.split() |> List.last() |> Macro.underscore(),
      attributes: %{},
      relationships: %{},
      creatable: [],
      updatable: []
    }
  end

  defp expand_resource(nil, schema, caller), do: convention_resource(schema, caller)

  defp expand_resource(resource, _schema, caller), do: Macro.expand(resource, caller)

  defp convention_resource({:__aliases__, _meta, parts}, caller) do
    parts
    |> Module.concat()
    |> convention_resource(caller)
  end

  defp convention_resource(module, caller) do
    module
    |> Macro.expand(caller)
    |> convention_resource()
  end

  defp convention_resource(module) do
    parts = Module.split(module)
    resource = parts |> List.last() |> pluralize_resource_name()
    namespace = Enum.drop(parts, -1)

    if List.last(namespace) == resource do
      Module.concat(namespace)
    else
      namespace
      |> Kernel.++([resource])
      |> Module.concat()
    end
  end

  defp pluralize_resource_name(name) do
    cond do
      String.ends_with?(name, "sis") ->
        String.replace_suffix(name, "sis", "ses")

      String.ends_with?(name, "y") and not vowel_before_suffix?(name, "y") ->
        String.replace_suffix(name, "y", "ies")

      Regex.match?(~r/(s|x|z|ch|sh)$/, name) ->
        name <> "es"

      true ->
        name <> "s"
    end
  end

  defp vowel_before_suffix?(name, suffix) do
    base = String.replace_suffix(name, suffix, "")

    case String.last(base) do
      nil -> false
      char -> char in ["a", "e", "i", "o", "u"]
    end
  end

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

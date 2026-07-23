defmodule Hawk.Model do
  @moduledoc """
  Thin schema DSL for Hawk-owned models.

  `Hawk.Model` keeps Ecto as the persistence layer, but lets a model declare
  association resource metadata at the association site. Hawk readers can then
  preload through the associated resource reader instead of duplicating preload
  query logic in policies.

  The external JSON:API shape of a resource lives in its sibling adapter
  (`MyApp.Courses.JsonApi`), not on the model. `Hawk.Model` only generates the
  resource convention (`__hawk_resource__/0`) and association metadata used by
  `Hawk.JsonApi.Schema` to discover the adapter.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Hawk.Model, only: [model: 2]

      Module.register_attribute(__MODULE__, :hawk_association_policies, accumulate: true)
      Module.register_attribute(__MODULE__, :hawk_association_readers, accumulate: true)
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

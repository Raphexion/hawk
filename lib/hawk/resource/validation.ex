defmodule Hawk.Resource.Validation do
  @moduledoc """
  Compile-time validation for `Hawk.Resource` facade declarations.

  Called from `Hawk.Resource.__using__/1` after the sibling modules are
  resolved. It fails fast with `ArgumentError` when a declared module is
  missing, a required function is absent, or an adapter contract (JSON:API
  sources, writable relationships, LiveView fields/filters/sorts) disagrees
  with the model or reader.

  This is the "do the declarations agree?" phase; code generation lives in
  `Hawk.Resource`.
  """

  @doc """
  Validates the resolved module map against their contracts.
  """
  def validate!(modules) do
    validate_module!(modules.model, :model)
    validate_module!(modules.reader, :reader)
    validate_module!(modules.policy, :policy)
    validate_module!(modules.writer, :writer)
    validate_module!(modules.json_api, :json_api)
    validate_module!(modules.live_view, :live_view)
    validate_module!(modules.actions, :actions)

    validate_functions!(modules.reader, :reader, all: 1, one: 1)
    validate_functions!(modules.policy, :policy, read_filter: 1)
    validate_functions!(modules.writer, :writer, create: 2, update: 3, delete: 2)
    validate_writer_form_contract!(modules.writer)
    validate_functions!(modules.json_api, :json_api, __hawk_json_api__: 0)
    validate_functions!(modules.live_view, :live_view, __hawk_live_view__: 0)
    validate_functions!(modules.actions, :actions, __hawk_actions__: 0)

    validate_json_api_contract!(modules.model, modules.json_api)
    validate_live_view_contract!(modules.model, modules.reader, modules.live_view)
  end

  defp validate_module!(false, _key), do: :ok

  defp validate_module!(module, key) when is_atom(module) do
    unless compiled?(module) do
      raise ArgumentError, "Hawk resource #{key} module #{inspect(module)} is not available"
    end
  end

  defp compiled?(module), do: match?({:module, ^module}, Code.ensure_compiled(module))

  defp validate_functions!(false, _key, _functions), do: :ok

  defp validate_functions!(module, key, functions) do
    Enum.each(functions, fn {function, arity} ->
      unless function_exported?(module, function, arity) do
        raise ArgumentError,
              "Hawk resource #{key} module #{inspect(module)} must define #{function}/#{arity}"
      end
    end)
  end

  defp validate_writer_form_contract!(false), do: :ok

  defp validate_writer_form_contract!(writer) do
    create? = function_exported?(writer, :change_create, 2)
    update? = function_exported?(writer, :change_update, 3)

    cond do
      create? and update? ->
        :ok

      create? ->
        raise ArgumentError,
              "Hawk resource writer module #{inspect(writer)} must define change_update/3 when change_create/2 is defined"

      update? ->
        raise ArgumentError,
              "Hawk resource writer module #{inspect(writer)} must define change_create/2 when change_update/3 is defined"

      true ->
        :ok
    end
  end

  defp validate_json_api_contract!(_model, false), do: :ok

  defp validate_json_api_contract!(model, json_api_module) do
    json_api = json_api_module.__hawk_json_api__()

    Enum.each(Map.get(json_api, :attributes, %{}), fn {name, metadata} ->
      source = Map.get(metadata, :source, name)

      if is_nil(model.__hawk_schema__(:type, source)) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} attribute #{inspect(name)} source #{inspect(source)} must reference a field on #{inspect(model)}"
      end
    end)

    Enum.each(Map.get(json_api, :relationships, %{}), fn {name, metadata} ->
      source = Map.get(metadata, :source, name)

      if is_nil(model.__hawk_schema__(:association, source)) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} relationship #{inspect(name)} source #{inspect(source)} must reference an association on #{inspect(model)}"
      end
    end)

    validate_json_api_capability!(json_api_module, json_api, :creatable)
    validate_json_api_capability!(json_api_module, json_api, :updatable)
    validate_json_api_writable_relationships!(model, json_api_module, json_api)
  end

  defp validate_json_api_capability!(json_api_module, json_api, capability) do
    declared =
      json_api
      |> Map.get(:attributes, %{})
      |> Map.keys()
      |> Kernel.++(Map.keys(Map.get(json_api, :relationships, %{})))
      |> MapSet.new()

    json_api
    |> Map.get(capability, [])
    |> Enum.each(fn name ->
      unless MapSet.member?(declared, name) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} #{capability} field #{inspect(name)} must be declared as an attribute or relationship"
      end
    end)
  end

  defp validate_json_api_writable_relationships!(model, json_api_module, json_api) do
    writable =
      json_api
      |> Map.get(:creatable, [])
      |> Kernel.++(Map.get(json_api, :updatable, []))
      |> Enum.uniq()
      |> MapSet.new()

    json_api
    |> Map.get(:relationships, %{})
    |> Enum.each(&validate_json_api_writable_relationship!(model, json_api_module, writable, &1))
  end

  defp validate_json_api_writable_relationship!(
         model,
         json_api_module,
         writable,
         {name, metadata}
       ) do
    if MapSet.member?(writable, name) do
      validate_json_api_writable_relationship!(model, json_api_module, name, metadata)
    end
  end

  defp validate_json_api_writable_relationship!(model, json_api_module, name, metadata) do
    source = Map.get(metadata, :source, name)
    association = model.__hawk_schema__(:association, source)

    unless match?(%Ecto.Association.BelongsTo{}, association) do
      raise ArgumentError,
            "Hawk resource json_api module #{inspect(json_api_module)} relationship #{inspect(name)} is writable but references a #{inspect(association.cardinality)} association on #{inspect(model)}; only belongs_to relationships can be mapped to writer attrs"
    end
  end

  defp validate_live_view_contract!(_model, _reader, false), do: :ok

  defp validate_live_view_contract!(model, reader, live_view_module) do
    live_view = live_view_module.__hawk_live_view__()

    index = live_view[:index] || %{}

    validate_live_view_filters!(
      live_view_module,
      reader,
      Map.get(index, :filters, []) ++ live_view_search_names(index)
    )

    validate_live_view_sorts!(
      live_view_module,
      reader,
      Map.get(index, :sorts, [])
    )

    validate_live_view_fields!(
      model,
      live_view_module,
      :index,
      Map.get(index, :table, [])
    )

    validate_live_view_fields!(
      model,
      live_view_module,
      :show,
      Map.get(live_view[:show] || %{}, :fields, [])
    )

    validate_live_view_fields!(
      model,
      live_view_module,
      :create_form,
      Map.get(live_view[:create_form] || %{}, :fields, [])
    )

    validate_live_view_fields!(
      model,
      live_view_module,
      :update_form,
      Map.get(live_view[:update_form] || %{}, :fields, [])
    )
  end

  defp validate_live_view_filters!(_live_view_module, _reader, []), do: :ok

  defp validate_live_view_filters!(live_view_module, reader, filters) do
    if function_exported?(reader, :filter_keys, 0) do
      validate_live_view_filters!(
        live_view_module,
        reader,
        filters,
        MapSet.new(reader.filter_keys())
      )
    end
  end

  defp validate_live_view_filters!(live_view_module, reader, filters, allowed) do
    Enum.each(filters, fn filter ->
      unless MapSet.member?(allowed, filter) do
        raise ArgumentError,
              "Hawk resource live_view module #{inspect(live_view_module)} index filter #{inspect(filter)} must be declared by reader #{inspect(reader)}"
      end
    end)
  end

  defp validate_live_view_sorts!(_live_view_module, _reader, []), do: :ok

  defp validate_live_view_sorts!(live_view_module, reader, sorts) do
    if function_exported?(reader, :sort_keys, 0) do
      validate_live_view_sorts!(live_view_module, reader, sorts, MapSet.new(reader.sort_keys()))
    end
  end

  defp validate_live_view_sorts!(live_view_module, reader, sorts, allowed) do
    Enum.each(sorts, fn sort ->
      unless MapSet.member?(allowed, sort) do
        raise ArgumentError,
              "Hawk resource live_view module #{inspect(live_view_module)} index sort #{inspect(sort)} must be declared by reader #{inspect(reader)}"
      end
    end)
  end

  defp live_view_search_names(index) do
    index
    |> Map.get(:searches, [])
    |> Enum.map(&Map.fetch!(&1, :name))
  end

  defp validate_live_view_fields!(model, live_view_module, kind, fields) do
    Enum.each(fields, fn metadata ->
      name = Map.fetch!(metadata, :name)
      source = Map.get(metadata, :source, name)

      if is_nil(model.__hawk_schema__(:type, source)) do
        raise ArgumentError,
              "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field #{inspect(name)} source #{inspect(source)} must reference a field on #{inspect(model)}"
      end
    end)
  end
end

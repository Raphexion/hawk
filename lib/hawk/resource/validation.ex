defmodule Hawk.Resource.Validation do
  @moduledoc """
  Compile-time validation for `Hawk.Resource` facade declarations.

  Called from `Hawk.Resource.__using__/1` after the sibling modules are
  resolved. It is the "do the declarations agree?" phase; code generation lives
  in `Hawk.Resource`.

  Validation runs in two modes:

    * `:compile` (default) — emitted from `use Hawk.Resource`. A *missing*
      sibling module (not yet compiled) produces a warning and skips that
      module's shape checks, so a facade can compile before its siblings
      during incremental edits or code generation. A *present but malformed*
      sibling still raises, because that is real contract drift, not a
      write-order artifact.
    * `:strict` — used by `mix hawk.validate`. Missing modules raise, so the
      task is the authoritative gate that a generator or CI runs once the
      whole resource set is written.

  The split keeps loud drift detection (the valuable part) while removing the
  write-order coupling that made Hawk codegen-hostile.
  """

  @type mode :: :compile | :strict

  @doc """
  Validates the resolved module map against their contracts.

  `mode` defaults to `:compile` (warn on missing siblings, raise on drift).
  Pass `:strict` to raise on missing siblings too — used by `mix hawk.validate`.
  """
  @spec validate!(map(), mode()) :: :ok
  def validate!(modules, mode \\ :compile) when mode in [:compile, :strict] do
    # The model is required and every other check depends on it. Without it
    # there is nothing useful to validate, so warn/raise on it alone and stop.
    if available?(modules.model, :model, mode) do
      validate_identity!(modules.model, Map.get(modules, :identity, :id))

      flags = %{
        reader: available?(modules.reader, :reader, mode),
        policy: available?(modules.policy, :policy, mode),
        writer: available?(modules.writer, :writer, mode),
        json_api: available?(modules.json_api, :json_api, mode),
        live_view: available?(modules.live_view, :live_view, mode),
        actions: available?(modules.actions, :actions, mode)
      }

      run_validations(modules, flags)
    end

    :ok
  end

  defp run_validations(modules, flags) do
    if flags.reader, do: validate_functions!(modules.reader, :reader, all: 1, one: 1)
    if flags.policy, do: validate_functions!(modules.policy, :policy, read_filter: 1)

    if flags.writer do
      validate_functions!(modules.writer, :writer, create: 2, update: 3, delete: 2)
      validate_writer_form_contract!(modules.writer)
    end

    if flags.json_api do
      validate_functions!(modules.json_api, :json_api, __hawk_json_api__: 0)
      validate_json_api_contract!(modules.model, modules.json_api)
    end

    if flags.live_view do
      validate_functions!(modules.live_view, :live_view, __hawk_live_view__: 0)
    end

    if flags.live_view and flags.reader do
      validate_live_view_contract!(modules.model, modules.reader, modules.live_view)
    end

    if flags.actions, do: validate_functions!(modules.actions, :actions, __hawk_actions__: 0)
  end

  defp available?(false, _key, _mode), do: false

  defp available?(module, key, :strict) when is_atom(module) do
    unless compiled?(module) do
      raise ArgumentError, "Hawk resource #{key} module #{inspect(module)} is not available"
    end

    true
  end

  defp available?(module, key, :compile) when is_atom(module) do
    if compiled?(module) do
      true
    else
      warn_missing(key, module)
      false
    end
  end

  defp warn_missing(key, module) do
    IO.warn(
      "Hawk resource #{key} module #{inspect(module)} is not available yet; " <>
        "skipping its contract validation. Run `mix hawk.validate` to enforce."
    )
  end

  defp validate_identity!(model, identity) when is_atom(identity) do
    unless identity in model.__schema__(:fields) do
      raise ArgumentError,
            "Hawk resource identity #{inspect(identity)} must be a field on #{inspect(model)}; " <>
              "declare it with `use Hawk.Resource, model: ..., identity: #{inspect(identity)}` " <>
              "or pick an existing field"
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

      if is_nil(model.__schema__(:type, source)) and not computed_attribute?(metadata) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} attribute #{inspect(name)} source #{inspect(source)} must reference a field on #{inspect(model)}"
      end
    end)

    Enum.each(Map.get(json_api, :relationships, %{}), fn {name, metadata} ->
      source = Map.get(metadata, :source, name)
      association = model.__schema__(:association, source)

      if is_nil(association) do
        raise ArgumentError,
              "Hawk resource json_api module #{inspect(json_api_module)} relationship #{inspect(name)} source #{inspect(source)} must reference an association on #{inspect(model)}"
      end

      validate_belongs_to_identity!(json_api_module, model, name, source, association)
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
    association = model.__schema__(:association, source)

    unless match?(%Ecto.Association.BelongsTo{}, association) do
      raise ArgumentError,
            "Hawk resource json_api module #{inspect(json_api_module)} relationship #{inspect(name)} is writable but references a #{inspect(association.cardinality)} association on #{inspect(model)}; only belongs_to relationships can be mapped to writer attrs"
    end
  end

  defp validate_belongs_to_identity!(
         json_api_module,
         _model,
         name,
         source,
         %Ecto.Association.BelongsTo{} = association
       ) do
    related = association.related
    related_identity = Hawk.JsonApi.Schema.identity(related)

    unless association.related_key == related_identity do
      raise ArgumentError,
            "Hawk resource json_api module #{inspect(json_api_module)} relationship #{inspect(name)} (source #{inspect(source)}) is a belongs_to whose related key " <>
              "#{inspect(association.related_key)} does not match the related resource #{inspect(related)} identity " <>
              "#{inspect(related_identity)}. Hawk renders belongs_to linkage from the foreign key " <>
              "value, so the foreign key must be the related resource's identity field. " <>
              "Either rename the foreign key to match the identity, or expose the relationship " <>
              "through a writer/action workflow that loads the related record."
    end
  end

  defp validate_belongs_to_identity!(_json_api_module, _model, _name, _source, _association) do
    :ok
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
      reader,
      live_view_module,
      :index,
      Map.get(index, :table, [])
    )

    validate_live_view_fields!(
      model,
      reader,
      live_view_module,
      :show,
      Map.get(live_view[:show] || %{}, :fields, [])
    )

    validate_live_view_fields!(
      model,
      reader,
      live_view_module,
      :create_form,
      Map.get(live_view[:create_form] || %{}, :fields, [])
    )

    validate_live_view_fields!(
      model,
      reader,
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

  defp computed_attribute?(%{resolver: resolver}) when is_function(resolver, 1), do: true
  defp computed_attribute?(%{resolver: resolver}) when is_function(resolver, 2), do: true
  defp computed_attribute?(_metadata), do: false

  defp validate_live_view_fields!(model, reader, live_view_module, kind, fields) do
    preload_keys = reader_preload_keys(reader)

    Enum.each(fields, fn metadata ->
      name = Map.fetch!(metadata, :name)
      source = Map.get(metadata, :source, name)
      validate_live_view_field!(model, live_view_module, kind, name, source, preload_keys)
    end)
  end

  defp validate_live_view_field!(model, live_view_module, kind, name, source, _preload_keys)
       when is_atom(source) do
    if is_nil(model.__schema__(:type, source)) do
      raise ArgumentError,
            "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field #{inspect(name)} " <>
              "source #{inspect(source)} must reference a field on #{inspect(model)}"
    end
  end

  defp validate_live_view_field!(_model, live_view_module, kind, name, [association | _rest], _preload_keys)
       when kind in [:create_form, :update_form] and is_atom(association) do
    raise ArgumentError,
          "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field #{inspect(name)} " <>
            "uses a path source #{inspect(association)}; form fields bind to root-model attrs the " <>
            "writer casts, not preloaded associations. Render a related value with a show field instead"
  end

  defp validate_live_view_field!(model, live_view_module, kind, name, [association | rest], preload_keys)
       when is_atom(association) do
    case model.__schema__(:association, association) do
      nil ->
        raise ArgumentError,
              "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field #{inspect(name)} " <>
                "source #{inspect([association | rest])} must reference an association on #{inspect(model)}"

      association_meta ->
        unless MapSet.member?(preload_keys, association) do
          raise ArgumentError,
                "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field #{inspect(name)} " <>
                  "reaches association #{inspect(association)}, which must be declared as a reader preload"
        end

        validate_path_tail(association_meta.related, live_view_module, kind, name, rest)
    end
  end

  defp validate_path_tail(_related, _live_view_module, _kind, _name, []), do: :ok

  defp validate_path_tail(related, live_view_module, kind, name, [key | rest]) when is_atom(key) do
    cond do
      not is_nil(related.__schema__(:type, key)) ->
        # Leaf field — the display target. Nothing more to preload.
        :ok

      association = related.__schema__(:association, key) ->
        # A nested association in the path must be preloaded by *its* resource's
        # reader, not just exist on the schema — otherwise the contract passes
        # but the runtime preload fails (the exact drift this check prevents).
        nested_preloads = reader_preload_keys(Hawk.Resource.Convention.reader_module(related))

        unless MapSet.member?(nested_preloads, key) do
          raise ArgumentError,
                "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field " <>
                  "#{inspect(name)} reaches nested association #{inspect(key)} on " <>
                  "#{inspect(related)}, which must be declared as a reader preload by " <>
                  "#{inspect(Hawk.Resource.Convention.reader_module(related))}"
        end

        validate_path_tail(association.related, live_view_module, kind, name, rest)

      true ->
        raise ArgumentError,
              "Hawk resource live_view module #{inspect(live_view_module)} #{kind} field " <>
                "#{inspect(name)} path #{inspect(key)} must reference a field or association on " <>
                "#{inspect(related)}"
    end
  end

  defp reader_preload_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_keys, 0) do
      reader.preload_keys()
    else
      MapSet.new()
    end
  end
end

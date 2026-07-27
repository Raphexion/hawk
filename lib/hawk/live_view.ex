defmodule Hawk.LiveView do
  @moduledoc """
  Small Phoenix LiveView helper DSL for Hawk resources.

  Hawk runs in Phoenix LiveViews and assigns through `Phoenix.Component.assign/3`
  and `Phoenix.Component.to_form/2` on real `Phoenix.LiveView.Socket` structs.
  """

  alias Hawk.LiveView
  alias Hawk.LiveView.IndexState

  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    validate_live_view_enabled!(resource)
    as = Keyword.get(opts, :as) || infer_as!(resource)
    plural_as = Keyword.get(opts, :plural_as) || infer_plural_as(resource, as)
    capabilities = live_view_capabilities(resource)
    live_view = live_view_metadata(resource)
    events? = Keyword.get(opts, :events, true)
    label_resolver = opts |> Keyword.get(:label_resolver) |> expand_optional_module(env)

    quote do
      def assign_index(socket, authority, opts \\ []) do
        LiveView.assign_index(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          authority,
          opts,
          unquote(Macro.escape(live_view))
        )
      end

      def assign_show(socket, authority, id, opts \\ []) do
        LiveView.assign_show(
          socket,
          unquote(resource),
          unquote(as),
          authority,
          id,
          opts,
          unquote(Macro.escape(live_view))
        )
      end

      def hawk_field_label(field) do
        LiveView.field_label(field, label_resolver: unquote(Macro.escape(label_resolver)))
      end

      def hawk_field_value(model, field) do
        LiveView.field_value(model, field)
      end

      def assign_read_form(socket, model, opts \\ []) do
        LiveView.assign_read_form(socket, unquote(as), model, opts, unquote(Macro.escape(live_view)))
      end

      unquote(quote_form_helpers(resource, as, capabilities, events?, live_view))
      unquote(quote_delete_handler(resource, as, plural_as, capabilities, live_view, events?))
    end
  end

  defp expand_optional_module(nil, _env), do: nil
  defp expand_optional_module(module, env), do: Macro.expand(module, env)

  defp live_view_capabilities(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) do
      resource.__hawk_resource__(:capabilities)
    else
      %{writer: true}
    end
  end

  defp quote_form_helpers(resource, as, _capabilities, events?, live_view) do
    if function_exported?(resource, :change_create, 2) and
         function_exported?(resource, :change_update, 3) do
      quote do
        def assign_new_form(socket, authority, attrs \\ %{}) do
          LiveView.assign_new_form(
            socket,
            unquote(resource),
            unquote(as),
            authority,
            attrs,
            unquote(Macro.escape(live_view))
          )
        end

        def assign_edit_form(socket, model, authority, attrs \\ %{}) do
          LiveView.assign_edit_form(
            socket,
            unquote(resource),
            unquote(as),
            model,
            authority,
            attrs,
            unquote(Macro.escape(live_view))
          )
        end

        def hawk_validate(params, socket) do
          LiveView.handle_validate(socket, unquote(resource), unquote(as), params)
        end

        def hawk_save(params, socket, opts \\ []) do
          LiveView.handle_save(socket, unquote(resource), unquote(as), params, opts)
        end

        unquote(quote_form_event_handlers(events?))
      end
    else
      []
    end
  end

  defp quote_form_event_handlers(false), do: []

  defp quote_form_event_handlers(true) do
    quote do
      def handle_event("hawk:validate", params, socket) do
        hawk_validate(params, socket)
      end

      def handle_event("hawk:save", params, socket) do
        hawk_save(params, socket)
      end
    end
  end

  defp quote_delete_handler(_resource, _as, _plural_as, _capabilities, _live_view, false), do: []

  defp quote_delete_handler(resource, as, plural_as, _capabilities, live_view, true) do
    quote do
      def handle_event("hawk:delete", params, socket) do
        LiveView.handle_delete(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          params,
          unquote(Macro.escape(live_view))
        )
      end
    end
  end

  defp validate_live_view_enabled!(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) and
         resource.__hawk_resource__(:live_view) == false do
      raise ArgumentError, "Hawk LiveView resource #{inspect(resource)} has live_view disabled"
    end
  end

  defp infer_as!(resource) do
    cond do
      Code.ensure_compiled(resource) != {:module, resource} ->
        raise ArgumentError, "Hawk LiveView resource #{inspect(resource)} is not available"

      function_exported?(resource, :__hawk_resource__, 1) ->
        resource
        |> live_view_metadata()
        |> Map.get(:as, model_as(resource.__hawk_resource__(:model)))

      true ->
        raise ArgumentError,
              "Hawk LiveView requires :as when resource #{inspect(resource)} is not a Hawk.Resource facade"
    end
  end

  defp infer_plural_as(resource, as) do
    resource
    |> live_view_metadata()
    |> Map.get(:plural_as, pluralize(as))
  end

  defp live_view_metadata(resource) do
    if function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(:live_view) do
        false -> %{}
        live_view -> live_view.__hawk_live_view__()
      end
    else
      %{}
    end
  end

  defp model_as(model) do
    model
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  def assign_index(socket, resource, as, plural_as, authority, opts \\ []) do
    assign_index(socket, resource, as, plural_as, authority, opts, %{})
  end

  def assign_index(socket, resource, as, plural_as, authority, opts, live_view) do
    state = IndexState.normalize(Keyword.get(opts, :params, %{}), live_view)

    reader_opts =
      opts
      |> Keyword.delete(:params)
      |> put_reader_filter(state.filter)
      |> put_reader_page(state.page)
      |> Keyword.put(:authority, authority)

    results = resource.all(reader_opts)
    page = Keyword.get(reader_opts, :page, %{})

    socket
    |> assign(:hawk_resource, as)
    |> assign(:hawk_index_state, state)
    |> assign(:hawk_index_meta, index_meta(as, plural_as, results, page))
    |> assign(:hawk_page, page)
    |> assign(:hawk_table, live_view_table(live_view))
    |> assign(plural_as, results)
  end

  def assign_show(socket, resource, as, authority, id, opts \\ []) do
    assign_show(socket, resource, as, authority, id, opts, %{})
  end

  def assign_show(socket, resource, as, authority, id, opts, live_view) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)
    lookup = Keyword.get(opts, :lookup, identity)

    opts =
      opts
      |> Keyword.delete(:lookup)
      |> Keyword.put(:authority, authority)
      |> Keyword.update(:filter, %{lookup => normalize_id(id)}, &Map.put(&1, lookup, normalize_id(id)))

    case resource.one(opts) do
      {:ok, model} ->
        socket
        |> assign(:hawk_resource, as)
        |> assign(:hawk_fields, live_view_fields(live_view))
        |> assign(as, model)

      :not_found ->
        assign(socket, :hawk_error, %{
          base: ["#{String.replace(to_string(as), "_", " ")} was not found"]
        })
    end
  end

  def assign_read_form(socket, as, model, opts \\ [], live_view \\ %{}) do
    fields = live_view |> form_fields(:update_form, Keyword.get(opts, :hidden, [])) |> fallback_read_fields(live_view)

    socket
    |> put_form_state(as, %{mode: :read, model: model})
    |> assign(form_assign(as), Phoenix.Component.to_form(read_form_data(model), as: as))
    |> assign(form_fields_assign(as), fields)
  end

  def assign_new_form(socket, resource, as, authority, attrs \\ %{}) do
    assign_new_form(socket, resource, as, authority, attrs, %{})
  end

  def assign_new_form(socket, resource, as, authority, opts, live_view) do
    opts = normalize_form_options(opts)
    attrs = merge_forced_attrs(opts.attrs, opts.forced_attrs)
    changeset = resource.change_create(attrs, authority)

    socket
    |> put_form_state(as, %{mode: :create, authority: authority, forced_attrs: opts.forced_attrs})
    |> assign(form_assign(as), form_value(socket, changeset, as))
    |> assign(form_fields_assign(as), form_fields(live_view, :create_form, opts.hidden))
  end

  def assign_edit_form(socket, resource, as, model, authority, attrs \\ %{}) do
    assign_edit_form(socket, resource, as, model, authority, attrs, %{})
  end

  def assign_edit_form(socket, resource, as, model, authority, opts, live_view) do
    opts = normalize_form_options(opts)
    attrs = merge_forced_attrs(opts.attrs, opts.forced_attrs)
    changeset = resource.change_update(model, attrs, authority)

    socket
    |> put_form_state(as, %{
      mode: :update,
      model: model,
      authority: authority,
      forced_attrs: opts.forced_attrs
    })
    |> assign(form_assign(as), form_value(socket, changeset, as))
    |> assign(form_fields_assign(as), form_fields(live_view, :update_form, opts.hidden))
  end

  def handle_validate(socket, resource, as, params) do
    form_params = Map.get(params, to_string(as), %{})
    state = socket.assigns.hawk_form_states[as]
    form_params = merge_forced_attrs(form_params, Map.get(state, :forced_attrs, %{}))

    changeset =
      case state.mode do
        :create -> resource.change_create(form_params, state.authority)
        :update -> resource.change_update(state.model, form_params, state.authority)
      end

    {:noreply, assign(socket, form_assign(as), form_value(socket, changeset, as))}
  end

  def handle_save(socket, resource, as, params, opts \\ []) do
    form_params = Map.get(params, to_string(as), %{})
    state = socket.assigns.hawk_form_states[as]
    form_params = merge_forced_attrs(form_params, Map.get(state, :forced_attrs, %{}))

    result =
      case state.mode do
        :create -> resource.create(form_params, state.authority)
        :update -> resource.update(state.model, form_params, state.authority)
      end

    {:noreply, apply_save_result(socket, resource, as, state, result, opts)}
  end

  defp apply_save_result(socket, _resource, as, _state, {:ok, model}, opts) do
    socket =
      socket
      |> assign(as, model)
      |> assign_edit_form_from_save(as, model)

    case Keyword.get(opts, :on_success) do
      nil -> socket
      callback when is_function(callback, 2) -> callback.(socket, model)
    end
  end

  defp apply_save_result(socket, _resource, as, %{mode: :create}, {:invalid, context}, _opts) do
    assign(socket, form_assign(as), form_value(socket, %{context.changeset | action: :insert}, as))
  end

  defp apply_save_result(socket, _resource, as, %{mode: :update}, {:invalid, context}, _opts) do
    assign(socket, form_assign(as), form_value(socket, %{context.changeset | action: :update}, as))
  end

  defp apply_save_result(
         socket,
         _resource,
         _as,
         _state,
         {:not_authorized, _context} = result,
         _opts
       ) do
    assign(socket, :hawk_error, live_error(result))
  end

  defp apply_save_result(socket, _resource, _as, _state, result, _opts) do
    assign(socket, :hawk_error, live_error(result))
  end

  defp assign_edit_form_from_save(socket, as, model) do
    state = socket.assigns.hawk_form_states[as]
    authority = state.authority

    changeset = %{Ecto.Changeset.change(model) | action: :validate}

    socket
    |> put_form_state(as, %{mode: :update, model: model, authority: authority})
    |> assign(form_assign(as), form_value(socket, changeset, as))
  end

  def handle_delete(socket, resource, as, plural_as, params) do
    handle_delete(socket, resource, as, plural_as, params, %{})
  end

  def handle_delete(
        socket,
        resource,
        as,
        plural_as,
        %{"id" => id, "authority" => authority},
        live_view
      ) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.one(authority: authority, filter: %{identity => normalize_id(id)}) do
      {:ok, model} ->
        case resource.delete(model, authority) do
          {:ok, _model} ->
            {:noreply, assign_index(socket, resource, as, plural_as, authority, [], live_view)}

          result ->
            {:noreply, assign(socket, :hawk_error, live_error(result))}
        end

      :not_found ->
        {:noreply,
         assign(socket, :hawk_error, %{
           base: ["#{String.replace(to_string(as), "_", " ")} was not found"]
         })}
    end
  end

  defp put_reader_filter(opts, :all), do: opts

  defp put_reader_filter(opts, filter),
    do: Keyword.update(opts, :filter, filter, &Hawk.Filter.and(&1, filter))

  defp put_reader_page(opts, page) when page == %{}, do: opts

  defp put_reader_page(opts, page) do
    Keyword.update(opts, :page, page, &Map.merge(&1, page))
  end

  def field_label(field, opts \\ []) do
    field
    |> Map.get(:label, {:humanize, Map.fetch!(field, :name)})
    |> resolve_label(Keyword.get(opts, :label_resolver))
  end

  def field_value(model, field) when is_map(field) do
    source = Map.get(field, :source, Map.fetch!(field, :name))
    value = Map.get(model, source)

    field
    |> Map.get(:format)
    |> apply_field_format(value, model, field)
  end

  defp resolve_label({:gettext, msgid} = label, resolver),
    do: resolve_with_app(label, resolver, msgid)

  defp resolve_label({:dgettext, _domain, msgid} = label, resolver),
    do: resolve_with_app(label, resolver, msgid)

  defp resolve_label({:humanize, name}, _resolver), do: humanize(name)
  defp resolve_label(label, _resolver) when is_binary(label), do: label

  defp resolve_with_app(_label, nil, fallback), do: fallback

  defp resolve_with_app(label, resolver, fallback) when is_atom(resolver) do
    if function_exported?(resolver, :field_label, 1) do
      resolver.field_label(label)
    else
      fallback
    end
  end

  defp apply_field_format(nil, value, _model, _field), do: value
  defp apply_field_format(format, value, _model, _field) when is_function(format, 1), do: format.(value)
  defp apply_field_format(format, value, model, _field) when is_function(format, 2), do: format.(value, model)
  defp apply_field_format(format, value, model, field) when is_function(format, 3), do: format.(value, model, field)

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp live_view_table(live_view), do: live_view |> Map.get(:index, %{}) |> Map.get(:table, [])
  defp live_view_fields(live_view), do: live_view |> Map.get(:show, %{}) |> Map.get(:fields, [])

  defp put_form_state(socket, as, state) do
    states = socket.assigns |> Map.get(:hawk_form_states, %{}) |> Map.put(as, state)
    assign(socket, :hawk_form_states, states)
  end

  defp normalize_form_options(opts) when is_list(opts) do
    %{
      attrs: Keyword.get(opts, :attrs, %{}),
      forced_attrs: Keyword.get(opts, :forced_attrs, %{}),
      hidden: Keyword.get(opts, :hidden, [])
    }
  end

  defp normalize_form_options(attrs) when is_map(attrs) do
    %{attrs: attrs, forced_attrs: %{}, hidden: []}
  end

  defp merge_forced_attrs(attrs, forced_attrs),
    do: Map.merge(attrs, stringify_forced_attrs(attrs, forced_attrs))

  defp stringify_forced_attrs(attrs, forced_attrs) do
    if Enum.any?(attrs, fn {key, _value} -> is_binary(key) end) do
      Map.new(forced_attrs, fn {key, value} -> {to_string(key), value} end)
    else
      forced_attrs
    end
  end

  defp read_form_data(model) when is_struct(model) do
    model
    |> Map.from_struct()
    |> Map.reject(fn {_key, value} -> match?(%Ecto.Association.NotLoaded{}, value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp read_form_data(model), do: model

  defp form_assign(as), do: :"#{as}_form"
  defp form_fields_assign(as), do: :"#{as}_form_fields"

  defp fallback_read_fields([], live_view), do: live_view_fields(live_view)
  defp fallback_read_fields(fields, _live_view), do: fields

  defp index_meta(as, plural_as, results, page) do
    %{
      resource: as,
      plural_resource: plural_as,
      page: page,
      count: length(results),
      has_more?: index_has_more?(results, page)
    }
  end

  defp index_has_more?(results, %{size: size}) when is_integer(size), do: length(results) >= size
  defp index_has_more?(_results, _page), do: false

  defp form_fields(live_view, key, hidden) do
    hidden = MapSet.new(hidden)

    live_view
    |> Map.get(key, %{})
    |> Map.get(:fields, [])
    |> Enum.reject(&MapSet.member?(hidden, &1.name))
  end

  defp form_value(_socket, changeset, as), do: Phoenix.Component.to_form(changeset, as: as)

  defp live_error(result) do
    case Hawk.Errors.to_live_view(result) do
      {:error, errors} -> errors
    end
  end

  defp assign(socket, key, value), do: Phoenix.Component.assign(socket, key, value)

  defp normalize_id(id), do: id

  defp pluralize(as) do
    as
    |> to_string()
    |> Kernel.<>("s")
    |> String.to_atom()
  end
end

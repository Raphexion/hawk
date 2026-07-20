defmodule Hawk.LiveView do
  @moduledoc """
  Small Phoenix LiveView helper DSL for Hawk resources.

  Hawk is intended to run in Phoenix LiveViews. The generated helpers delegate to
  `Phoenix.Component.assign/3` when available; plain map sockets remain supported
  as a lightweight test boundary.
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

      unquote(quote_form_helpers(resource, as, capabilities, events?))
      unquote(quote_delete_handler(resource, as, plural_as, capabilities, live_view, events?))
    end
  end

  defp live_view_capabilities(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) do
      resource.__hawk_resource__(:capabilities)
    else
      %{writer: true}
    end
  end

  defp quote_form_helpers(_resource, _as, %{writer: false}, _events?), do: []

  defp quote_form_helpers(resource, as, _capabilities, events?) do
    if function_exported?(resource, :change_create, 2) and
         function_exported?(resource, :change_update, 3) do
      quote do
        def assign_new_form(socket, authority, attrs \\ %{}) do
          LiveView.assign_new_form(socket, unquote(resource), unquote(as), authority, attrs)
        end

        def assign_edit_form(socket, model, authority, attrs \\ %{}) do
          LiveView.assign_edit_form(
            socket,
            unquote(resource),
            unquote(as),
            model,
            authority,
            attrs
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

  defp quote_delete_handler(_resource, _as, _plural_as, %{writer: false}, _live_view, _events?),
    do: []

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

    socket
    |> assign(:hawk_resource, as)
    |> assign(:hawk_index_state, state)
    |> assign(:hawk_page, Keyword.get(reader_opts, :page, %{}))
    |> assign(:hawk_table, live_view_table(live_view))
    |> assign(plural_as, results)
  end

  def assign_show(socket, resource, as, authority, id, opts \\ []) do
    assign_show(socket, resource, as, authority, id, opts, %{})
  end

  def assign_show(socket, resource, as, authority, id, opts, live_view) do
    opts =
      opts
      |> Keyword.put(:authority, authority)
      |> Keyword.update(:filter, %{id: normalize_id(id)}, &Map.put(&1, :id, normalize_id(id)))

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

  def assign_new_form(socket, resource, as, authority, attrs \\ %{}) do
    changeset = resource.change_create(attrs, authority)

    socket
    |> put_form_state(as, %{mode: :create, authority: authority})
    |> assign(form_assign(as), form_value(changeset, as))
  end

  def assign_edit_form(socket, resource, as, model, authority, attrs \\ %{}) do
    changeset = resource.change_update(model, attrs, authority)

    socket
    |> put_form_state(as, %{mode: :update, model: model, authority: authority})
    |> assign(form_assign(as), form_value(changeset, as))
  end

  def handle_validate(socket, resource, as, params) do
    form_params = Map.get(params, to_string(as), %{})
    state = socket.assigns.hawk_form_states[as]

    changeset =
      case state.mode do
        :create -> resource.change_create(form_params, state.authority)
        :update -> resource.change_update(state.model, form_params, state.authority)
      end

    {:noreply, assign(socket, form_assign(as), form_value(changeset, as))}
  end

  def handle_save(socket, resource, as, params, opts \\ []) do
    form_params = Map.get(params, to_string(as), %{})
    state = socket.assigns.hawk_form_states[as]

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
    assign(socket, form_assign(as), form_value(%{context.changeset | action: :insert}, as))
  end

  defp apply_save_result(socket, _resource, as, %{mode: :update}, {:invalid, context}, _opts) do
    assign(socket, form_assign(as), form_value(%{context.changeset | action: :update}, as))
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
    |> assign(form_assign(as), form_value(changeset, as))
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
    case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
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

  defp live_view_table(live_view), do: live_view |> Map.get(:index, %{}) |> Map.get(:table, [])
  defp live_view_fields(live_view), do: live_view |> Map.get(:show, %{}) |> Map.get(:fields, [])

  defp put_form_state(socket, as, state) do
    states = socket.assigns |> Map.get(:hawk_form_states, %{}) |> Map.put(as, state)
    assign(socket, :hawk_form_states, states)
  end

  defp form_assign(as), do: :"#{as}_form"

  defp form_value(changeset, as) do
    phoenix_component = Module.concat([Phoenix, Component])

    if Code.ensure_loaded?(phoenix_component) and
         function_exported?(phoenix_component, :to_form, 2) do
      phoenix_component.to_form(changeset, as: as)
    else
      changeset
    end
  end

  defp live_error(result) do
    case Hawk.Errors.to_live_view(result) do
      {:error, errors} -> errors
    end
  end

  defp assign(socket, key, value) do
    phoenix_component = Module.concat([Phoenix, Component])

    if Code.ensure_loaded?(phoenix_component) and
         function_exported?(phoenix_component, :assign, 3) do
      phoenix_component.assign(socket, key, value)
    else
      assigns = Map.get(socket, :assigns, %{})
      Map.put(socket, :assigns, Map.put(assigns, key, value))
    end
  end

  defp normalize_id(id), do: id

  defp pluralize(as) do
    as
    |> to_string()
    |> Kernel.<>("s")
    |> String.to_atom()
  end
end

defmodule Hawk.LiveView do
  @moduledoc """
  Small Phoenix LiveView helper DSL for Hawk resources.

  Hawk runs in Phoenix LiveViews and assigns through `Phoenix.Component.assign/3`
  and `Phoenix.Component.to_form/2` on real `Phoenix.LiveView.Socket` structs.
  """

  alias Hawk.LiveView
  alias Hawk.LiveView.IndexState

  @doc """
  Generates LiveView helpers for a Hawk resource.

  Emits assign helpers (`assign_index/3`, `assign_show/4`, `assign_read_form/3`,
  form helpers), field label/value helpers, and event handlers, all backed by
  the resource's reader/writer and the LiveView adapter metadata. Templates
  call these to render index/show/form screens.

  ## Options

    * `:resource` (required) — the `Hawk.Resource` facade.
    * `:as` / `:plural_as` — assign names (default: inferred from the resource).
    * `:events` — whether to generate event handlers (default `true`).
    * `:label_resolver` — a module providing `field_label/2` for translation.
  """
  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    validate_live_view_enabled!(resource)
    as = Keyword.get(opts, :as)
    plural_as = Keyword.get(opts, :plural_as)
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
          opts
        )
      end

      def assign_show(socket, authority, id, opts \\ []) do
        LiveView.assign_show(
          socket,
          unquote(resource),
          unquote(as),
          authority,
          id,
          opts
        )
      end

      def hawk_field_label(field) do
        LiveView.field_label(field, label_resolver: unquote(Macro.escape(label_resolver)))
      end

      def hawk_field_value(model, field) do
        LiveView.field_value(model, field)
      end

      def assign_read_form(socket, model, opts \\ []) do
        LiveView.assign_read_form(socket, unquote(resource), unquote(as), model, opts)
      end

      unquote(quote_form_helpers(resource, as, events?))
      unquote(quote_delete_handler(resource, as, plural_as, events?))
    end
  end

  defp expand_optional_module(nil, _env), do: nil
  defp expand_optional_module(module, env), do: Macro.expand(module, env)

  defp quote_form_helpers(resource, as, events?) do
    quote do
      def assign_new_form(socket, authority, attrs \\ %{}) do
        LiveView.assign_new_form(
          socket,
          unquote(resource),
          unquote(as),
          authority,
          attrs
        )
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

  defp quote_delete_handler(_resource, _as, _plural_as, false), do: []

  defp quote_delete_handler(resource, as, plural_as, true) do
    quote do
      def handle_event("hawk:delete", params, socket) do
        LiveView.handle_delete(
          socket,
          unquote(resource),
          unquote(as),
          unquote(plural_as),
          params
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

  defp live_view_metadata(resource) do
    if Code.ensure_loaded?(resource) and function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(:live_view) do
        false -> %{}
        live_view -> adapter_metadata(live_view)
      end
    else
      %{}
    end
  end

  defp adapter_metadata(live_view) when is_atom(live_view) do
    if Code.ensure_loaded?(live_view) and function_exported?(live_view, :__hawk_live_view__, 0) do
      live_view.__hawk_live_view__()
    else
      %{}
    end
  end

  defp resource_assigns(resource, live_view, as, plural_as) do
    as = as || Map.get(live_view, :as) || model_as(resource.__hawk_resource__(:model))
    plural_as = plural_as || Map.get(live_view, :plural_as) || pluralize(as)

    {as, plural_as}
  end

  defp model_as(model) do
    model
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  @doc false
  def assign_index(socket, resource, as, plural_as, authority, opts \\ []) do
    live_view = live_view_metadata(resource)
    {as, plural_as} = resource_assigns(resource, live_view, as, plural_as)
    state = IndexState.normalize(Keyword.get(opts, :params, %{}), live_view)
    model = resource.__hawk_resource__(:model)
    preloads = derive_preloads(live_view_table(live_view), model)

    reader_opts =
      opts
      |> reject_preloads_opt!()
      |> Keyword.delete(:params)
      |> put_reader_filter(state.filter)
      |> put_reader_page(state.page)
      |> put_reader_sort(state.sort)
      |> Keyword.put(:authority, authority)
      |> put_reader_preloads(preloads)

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

  @doc false
  def assign_show(socket, resource, as, authority, id, opts \\ []) do
    live_view = live_view_metadata(resource)
    {as, _plural_as} = resource_assigns(resource, live_view, as, nil)
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)
    lookup = Keyword.get(opts, :lookup, identity)
    model = resource.__hawk_resource__(:model)
    preloads = derive_preloads(live_view_fields(live_view), model)

    opts =
      opts
      |> reject_preloads_opt!()
      |> Keyword.delete(:lookup)
      |> Keyword.put(:authority, authority)
      |> Keyword.update(:filter, %{lookup => normalize_id(id)}, &Map.put(&1, lookup, normalize_id(id)))
      |> put_reader_preloads(preloads)

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

  @doc false
  def assign_read_form(socket, resource, as, model, opts \\ []) do
    live_view = live_view_metadata(resource)
    {as, _plural_as} = resource_assigns(resource, live_view, as, nil)
    fields = live_view |> form_fields(:update_form, Keyword.get(opts, :hidden, [])) |> fallback_read_fields(live_view)

    socket
    |> put_form_state(as, %{mode: :read, model: model})
    |> assign(form_assign(as), Phoenix.Component.to_form(read_form_data(model), as: as))
    |> assign(form_fields_assign(as), fields)
  end

  @doc false
  def assign_new_form(socket, resource, as, authority, opts \\ %{}) do
    live_view = live_view_metadata(resource)
    {as, _plural_as} = resource_assigns(resource, live_view, as, nil)
    opts = normalize_form_options(opts)
    attrs = merge_forced_attrs(opts.attrs, opts.forced_attrs)
    changeset = resource.change_create(attrs, authority)

    socket
    |> put_form_state(as, %{mode: :create, authority: authority, forced_attrs: opts.forced_attrs})
    |> assign(form_assign(as), form_value(socket, changeset, as))
    |> assign(form_fields_assign(as), form_fields(live_view, :create_form, opts.hidden))
  end

  @doc false
  def assign_edit_form(socket, resource, as, model, authority, opts \\ %{}) do
    live_view = live_view_metadata(resource)
    {as, _plural_as} = resource_assigns(resource, live_view, as, nil)
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

  @doc false
  def handle_validate(socket, resource, as, params) do
    {as, _plural_as} = resource_assigns(resource, live_view_metadata(resource), as, nil)
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

  @doc false
  def handle_save(socket, resource, as, params, opts \\ []) do
    {as, _plural_as} = resource_assigns(resource, live_view_metadata(resource), as, nil)
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

  @doc false
  def handle_delete(socket, resource, as, plural_as, %{"id" => id, "authority" => authority}) do
    live_view = live_view_metadata(resource)
    {as, plural_as} = resource_assigns(resource, live_view, as, plural_as)
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.one(authority: authority, filter: %{identity => normalize_id(id)}) do
      {:ok, model} ->
        case resource.delete(model, authority) do
          {:ok, _model} ->
            {:noreply, assign_index(socket, resource, as, plural_as, authority, [])}

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

  @doc """
  Validates a two-phase Action without committing, assigning the per-step
  changesets for live form rendering.

  The Action must declare `build: true` (or `build: :fn`) so that
  `<handler>_change/3` is generated. For a run-only Action (no `build:`), this
  assigns `:hawk_action_run_only` so the template can render a "validate by
  submitting" fallback.

  Assigns `:hawk_action_changesets` (`%{step_name => changeset}`) on success.
  """
  def hawk_validate_action(socket, resource, action_name, model, params, opts \\ []) do
    authority = action_authority(socket, opts)
    actions_module = Hawk.Actions.actions_module(resource)
    metadata = action_metadata!(resource, action_name)

    change_fn =
      case metadata do
        %{change_handler: handler} -> String.to_atom("#{handler}_change")
        _ -> String.to_atom("#{metadata.handler}_change")
      end

    cond do
      function_exported?(actions_module, change_fn, 3) ->
        changesets =
          apply(actions_module, change_fn, [
            model,
            Hawk.Actions.atomize_params(params, metadata),
            authority
          ])

        {:noreply, assign(socket, :hawk_action_changesets, changesets)}

      metadata.build == nil ->
        {:noreply, assign(socket, :hawk_action_run_only, true)}

      true ->
        {:noreply, assign(socket, :hawk_error, %{base: ["action #{action_name} is not validatable"]})}
    end
  end

  @doc """
  Commits an Action and applies the result to the socket.

  Routes through `Hawk.Actions.dispatch/5`, so a two-phase Action commits via
  its generated `<handler>_run/3` and a run-only Action commits via its
  hand-written handler. The `on_success` callback (set via `opts`) receives
  `(socket, results)` where `results` is the dispatch result — a map of step
  name to model for a two-phase Action, or the handler's single return value
  for a run-only Action.
  """
  def hawk_action(socket, resource, action_name, model, params, opts \\ []) do
    authority = action_authority(socket, opts)

    result = Hawk.Actions.dispatch(resource, action_name, model, params, authority)

    case result do
      {:ok, results} ->
        socket = assign(socket, :hawk_action_results, results)

        case Keyword.get(opts, :on_success) do
          nil -> {:noreply, socket}
          callback when is_function(callback, 2) -> {:noreply, callback.(socket, results)}
        end

      {:invalid, _context} = result ->
        {:noreply, assign(socket, :hawk_error, live_error(result))}

      {:not_authorized, _context} = result ->
        {:noreply, assign(socket, :hawk_error, live_error(result))}

      {:error, name, reason, _prior} ->
        {:noreply, assign(socket, :hawk_error, %{base: ["action step #{inspect(name)} failed: #{inspect(reason)}"]})}

      other ->
        {:noreply, assign(socket, :hawk_error, %{base: ["action failed: #{inspect(other)}"]})}
    end
  end

  defp action_authority(socket, opts) do
    Keyword.get(opts, :authority) || socket.assigns[:hawk_authority] || Hawk.Authority.public()
  end

  defp action_metadata!(resource, action_name) do
    case Map.fetch(Hawk.Actions.actions(resource), action_name) do
      {:ok, metadata} ->
        metadata

      :error ->
        raise ArgumentError, "unknown action #{inspect(action_name)} for #{inspect(resource)}"
    end
  end

  defp put_reader_filter(opts, :all), do: opts

  defp put_reader_filter(opts, filter),
    do: Keyword.update(opts, :filter, filter, &Hawk.Filter.and(&1, filter))

  defp put_reader_page(opts, page) when page == %{}, do: opts

  defp put_reader_page(opts, page) do
    Keyword.update(opts, :page, page, &Map.merge(&1, page))
  end

  defp put_reader_sort(opts, []), do: opts

  defp put_reader_sort(opts, sort), do: Keyword.put(opts, :sort, sort)

  defp put_reader_preloads(opts, []), do: opts

  defp put_reader_preloads(opts, preloads), do: Keyword.put(opts, :preloads, preloads)

  # The LiveView adapter is the single source of preloads: `assign_index` /
  # `assign_show` derive them from declared `source:` path columns and fields.
  # A caller-supplied `:preloads` would be a second source and drift from the
  # adapter, so it is rejected. Pass `preloads:` on the reader or page helper
  # for explicit control outside the adapter contract.
  defp reject_preloads_opt!(opts) do
    if Keyword.has_key?(opts, :preloads) do
      raise ArgumentError,
            "Hawk.LiveView assign_index/assign_show derive preloads from the LiveView " <>
              "adapter's `source:` paths; pass :preloads on the reader or assign_page instead"
    end

    opts
  end

  @doc false
  def field_label(field, opts \\ []) do
    field
    |> Map.get(:label, {:humanize, Map.fetch!(field, :name)})
    |> resolve_label(Keyword.get(opts, :label_resolver))
  end

  @doc false
  def field_value(model, field) when is_map(field) do
    source = Map.get(field, :source, Map.fetch!(field, :name))
    value = resolve_source(model, source)

    field
    |> Map.get(:format)
    |> apply_field_format(value, model, field)
  end

  defp resolve_source(model, source) when is_atom(source), do: Map.get(model, source)

  defp resolve_source(model, [association | rest]) when is_atom(association) do
    case Map.get(model, association) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      related -> walk_path(related, rest)
    end
  end

  defp walk_path(value, []), do: value
  defp walk_path(model, [key | rest]) when is_atom(key), do: walk_path(Map.get(model, key), rest)

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

  @doc false
  def derive_preloads(fields) do
    fields
    |> Enum.reduce(%{}, &merge_preload_spec(&1, &2))
    |> spec_to_list()
  end

  @doc false
  def derive_preloads(fields, model) do
    fields
    |> Enum.reduce(%{}, &merge_preload_spec(&1, &2, model))
    |> spec_to_list()
  end

  defp merge_preload_spec(field, acc) do
    case Map.get(field, :source) do
      [_ | _] = path -> merge_paths(acc, preload_path(path))
      _other -> acc
    end
  end

  defp merge_preload_spec(field, acc, model) do
    case Map.get(field, :source) do
      [_ | _] = path -> merge_paths(acc, preload_path(path, model))
      _other -> acc
    end
  end

  # A path source `[a, b, ..., z]` reaches associations `a, b, ...` and displays
  # the leaf `z`. The leaf is a field (or a whole association shown directly
  # when the path has one element), not a preload. So for a multi-element path,
  # drop the leaf and preload the remaining association chain; for a single
  # element, preload it.
  defp preload_path([single]), do: %{single => nil}

  defp preload_path([_leaf | _] = path) do
    path |> Enum.drop(-1) |> build_nested()
  end

  defp build_nested([single]), do: %{single => nil}
  defp build_nested([head | rest]), do: %{head => build_nested(rest)}

  # Model-aware variant: walk the path keeping every element that is an
  # association on the current schema, stopping at the first field (the display
  # leaf). This handles both display paths (`[:student, :name]` → preload
  # `:student`) and collection-iteration paths whose leaf is itself an
  # association (`[:grades, :student]` → preload `grades: [:student]`).
  defp preload_path(path, model), do: preload_path(path, model, %{})

  defp preload_path([head | rest], model, acc) do
    case model.__schema__(:association, head) do
      nil ->
        acc

      association ->
        nested = build_nested_from(rest, association.related)
        merge_paths(acc, %{head => nested})
    end
  end

  defp build_nested_from([], _model), do: nil

  defp build_nested_from([head | rest], model) do
    case model.__schema__(:association, head) do
      nil ->
        nil

      association ->
        case build_nested_from(rest, association.related) do
          nil -> %{head => nil}
          nested -> %{head => nested}
        end
    end
  end

  defp merge_paths(acc, spec) when is_map(acc) and is_map(spec) do
    Map.merge(acc, spec, fn _k, left, right -> merge_nested(left, right) end)
  end

  defp merge_nested(nil, nil), do: nil
  defp merge_nested(nil, right), do: right
  defp merge_nested(left, nil), do: left
  defp merge_nested(left, right) when is_map(left) and is_map(right), do: merge_paths(left, right)

  defp spec_to_list(spec) when is_map(spec) do
    Enum.map(spec, fn
      {key, nil} -> key
      {key, nested} -> {key, spec_to_list(nested)}
    end)
  end

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

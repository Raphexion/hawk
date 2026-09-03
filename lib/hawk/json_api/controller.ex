defmodule Hawk.JsonApi.Controller do
  @moduledoc """
  Phoenix controller helpers for Hawk JSON:API resources.

  Hawk runs behind Phoenix controllers and renders responses through `Plug.Conn`
  directly with the exact `application/vnd.api+json` content type. JSON:API does
  not permit a `charset` media-type parameter. Explicit request `Content-Type`
  values must be JSON:API with only `ext`/`profile` parameters; incompatible
  values return `415`. `Accept` must allow JSON:API (directly or by wildcard),
  otherwise Hawk returns `406`.
  """

  import Ecto.Query

  alias Hawk.JsonApi.Controller, as: JsonApiController
  alias Hawk.JsonApi.{ControllerSupport, Document, Request, Schema}

  @doc """
  Generates a Phoenix JSON:API controller for a Hawk resource.

  Emits `index/2`, `show/2`, `create/2`, `update/2`, `delete/2`,
  `relationship/2`, `related/2`, plus `hawk_action/2` for custom action
  dispatch. The writer is a required sibling for every Hawk
  resource, so the create/update/delete actions are always generated; writes
  are gated by the policy, not by the controller shape.

  ## Options

    * `:resource` (required) — the `Hawk.Resource` facade. The backing model is
      resolved from the facade.
    * `:public` — allow public (anonymous) read access (default `false`).
  """
  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    require_facade!(resource)
    model = resource.__hawk_resource__(:model)
    validate_json_api_enabled!(resource)
    public? = Keyword.get(opts, :public, false)
    reader = resource.__hawk_resource__(:reader)

    quote do
      use Phoenix.Controller, formats: []

      def index(conn, params) do
        JsonApiController.index(
          conn,
          unquote(resource),
          unquote(model),
          unquote(reader),
          params,
          unquote(public?)
        )
      end

      def show(conn, params) do
        JsonApiController.show(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      unquote(quote_writer_actions(resource, model, public?))
      unquote(quote_custom_action(resource, model, public?))

      def relationship(conn, params) do
        JsonApiController.relationship(
          conn,
          unquote(resource),
          unquote(model),
          unquote(reader),
          params,
          unquote(public?)
        )
      end

      def related(conn, params) do
        JsonApiController.related(
          conn,
          unquote(resource),
          unquote(model),
          unquote(reader),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp require_facade!(resource) do
    case Code.ensure_compiled(resource) do
      {:module, ^resource} ->
        if function_exported?(resource, :__hawk_resource__, 1) do
          :ok
        else
          raise ArgumentError,
                "Hawk JSON:API controller resource #{inspect(resource)} must be a Hawk.Resource facade"
        end

      _ ->
        raise ArgumentError,
              "Hawk JSON:API controller resource #{inspect(resource)} is not available"
    end
  end

  defp quote_writer_actions(resource, model, public?) do
    quote do
      def create(conn, params) do
        JsonApiController.create(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def update(conn, params) do
        JsonApiController.update(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def delete(conn, params) do
        JsonApiController.delete(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp quote_custom_action(resource, model, public?) do
    quote do
      def hawk_action(conn, params) do
        JsonApiController.action(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp validate_json_api_enabled!(resource) do
    if resource.__hawk_resource__(:json_api) == false do
      raise ArgumentError,
            "Hawk JSON:API controller resource #{inspect(resource)} has json_api disabled"
    end
  end

  @doc false
  def index(conn, resource, model, reader, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      fields = Request.sparse_fieldsets(params)

      select = read_select(resource, model, authority, fields)

      opts =
        params
        |> Request.request_options(reader: reader, model: model, authority: authority)
        |> Keyword.put(:authority, authority)
        |> Keyword.put(:context, request_context(conn))
        |> Keyword.put(:fields, fields)
        |> Keyword.put(:select, select)

      result = resource.page(opts)
      models = result.entries
      page = result.page

      document_opts =
        [
          authority: authority,
          preloads: Keyword.get(opts, :preloads, []),
          context: Keyword.get(opts, :context, %{}),
          page: page,
          fields: fields,
          has_more: result.has_more?,
          next_cursor: result.next_cursor
        ]
        |> maybe_put_total_count(resource, opts, result)

      document = Document.document(models, document_opts)

      json(conn, 200, document)
    end)
  end

  @doc false
  def show(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    do_show(conn, resource, model, id, params, public?)
  end

  defp do_show(conn, resource, _model, id, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      fields = Request.sparse_fieldsets(params)

      case Request.member_id!(id) do
        {:uuid, uuid} -> show_by_uuid(conn, resource, authority, context, uuid, fields)
        {:short_id, prefix} -> show_by_short_id(conn, resource, authority, context, prefix, fields)
      end
    end)
  end

  defp show_by_uuid(conn, resource, authority, context, uuid, fields) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)
    model = resource.__hawk_resource__(:model)
    select = read_select(resource, model, authority, fields)

    case resource.one(authority: authority, context: context, filter: %{identity => uuid}, select: select) do
      {:ok, model} ->
        json(
          conn,
          200,
          Document.document(model,
            authority: authority,
            context: context,
            links: true,
            fields: fields
          )
        )

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  defp show_by_short_id(conn, resource, authority, context, prefix, fields) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)
    model = resource.__hawk_resource__(:model)
    select = read_select(resource, model, authority, fields)

    case resource.all(
           authority: authority,
           context: context,
           filter: Request.short_id_filter(prefix, identity),
           page: %{size: 2},
           select: select
         ) do
      [model] ->
        json(
          conn,
          200,
          Document.document(model,
            authority: authority,
            context: context,
            links: true,
            fields: fields
          )
        )

      [] ->
        json(conn, 404, not_found(resource))

      [_first, _second | _rest] ->
        json(conn, 400, bad_request("id prefix #{inspect(prefix)} is ambiguous"))
    end
  end

  defp model_module(%module{}), do: module

  defp primary_result(results, primary_model) do
    Enum.find_value(results, fn {_name, value} ->
      if is_struct(value, primary_model), do: value
    end)
  end

  @doc false
  def create(conn, resource, model, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      Request.validate_document!(params, model, :creatable)

      params
      |> Request.attributes(model, :creatable)
      |> resource.create(authority)
      |> respond(conn, resource, model, 201)
    end)
  end

  @doc false
  def update(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    do_update(conn, resource, model, id, params, public?)
  end

  defp do_update(conn, resource, model, id, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      path_id = normalize_id(id)

      case resource.one(authority: authority, context: context, filter: %{identity => path_id}) do
        {:ok, existing} ->
          Request.validate_document!(params, model, :updatable, path_id: path_id)

          params
          |> Request.attributes(model, :updatable)
          |> then(&resource.update(existing, &1, authority))
          |> respond(conn, resource, model, 200)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  @doc false
  def delete(conn, resource, _model, %{"id" => id}, public? \\ false) do
    do_delete(conn, resource, id, public?)
  end

  defp do_delete(conn, resource, id, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      case resource.one(authority: authority, context: context, filter: %{identity => normalize_id(id)}) do
        {:ok, existing} -> respond_delete(conn, resource, existing, authority)
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  defp respond_delete(conn, resource, existing, authority) do
    case resource.delete(existing, authority) do
      {:ok, _deleted} -> no_content(conn)
      :ok -> no_content(conn)
      result -> respond(result, conn, resource, model_module(existing), 200)
    end
  end

  @doc false
  def action(
        conn,
        resource,
        _model,
        %{"id" => id, "action" => action_name} = params,
        public? \\ false
      ) do
    do_action(conn, resource, id, action_name, params, public?)
  end

  defp do_action(conn, resource, id, action_name, params, public?) do
    with_error_boundary(conn, fn ->
      Request.validate_action_document!(params)
      authority = authority!(conn, public?)
      context = request_context(conn)
      identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

      case resource.one(authority: authority, context: context, filter: %{identity => normalize_id(id)}) do
        {:ok, existing} ->
          respond_action(conn, resource, action_name, existing, params, authority)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  @doc false
  def relationship(
        conn,
        resource,
        model,
        reader,
        %{"id" => id, "relationship" => relationship_name} = params,
        public? \\ false
      ) do
    do_relationship(conn, resource, model, reader, id, relationship_name, params, public?)
  end

  defp do_relationship(conn, resource, model, reader, id, relationship_name, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      with_relationship(conn, model, relationship_name, authority, fn relationship ->
        render_relationship(%{
          conn: conn,
          resource: resource,
          model: model,
          reader: reader,
          id: id,
          relationship_name: relationship_name,
          relationship: relationship,
          authority: authority,
          params: params
        })
      end)
    end)
  end

  @doc false
  def related(
        conn,
        resource,
        model,
        reader,
        %{"id" => id, "relationship" => relationship_name} = params,
        public? \\ false
      ) do
    do_related(conn, resource, model, reader, id, relationship_name, params, public?)
  end

  defp do_related(conn, resource, model, reader, id, relationship_name, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      fields = Request.sparse_fieldsets(params)

      with_relationship(conn, model, relationship_name, authority, fn relationship ->
        render_related(%{
          conn: conn,
          resource: resource,
          reader: reader,
          id: id,
          relationship_name: relationship_name,
          relationship: relationship,
          authority: authority,
          fields: fields,
          params: params
        })
      end)
    end)
  end

  defp render_relationship(%{model: model, relationship: relationship} = request) do
    association = model.__schema__(:association, relationship)

    if direct_to_many_association?(association) do
      render_to_many_relationship(request)
    else
      render_preloaded_relationship(request, association)
    end
  end

  defp render_preloaded_relationship(%{} = request, association) do
    %{conn: conn, resource: resource, model: model, id: id, relationship_name: relationship_name} = request
    %{relationship: relationship, authority: authority} = request
    preloads = if match?(%{cardinality: :many}, association), do: [relationship], else: []
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)
    select = read_select(resource, model, authority, %{})

    case resource.one(
           authority: authority,
           context: request_context(conn),
           filter: %{identity => normalize_id(id)},
           preloads: preloads,
           select: select
         ) do
      {:ok, loaded} -> json(conn, 200, Document.relationship_document(loaded, relationship_name))
      :not_found -> json(conn, 404, not_found(resource))
    end
  end

  defp render_related(%{resource: resource, relationship: relationship} = request) do
    model = resource.__hawk_resource__(:model)
    association = model.__schema__(:association, relationship)

    if direct_to_many_association?(association) do
      request |> Map.put(:model, model) |> render_to_many_related()
    else
      render_preloaded_related(request, model)
    end
  end

  defp render_preloaded_related(%{} = request, model) do
    %{conn: conn, resource: resource, id: id, relationship_name: relationship_name} = request
    %{relationship: relationship, authority: authority, fields: fields} = request
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    case resource.one(
           authority: authority,
           context: request_context(conn),
           filter: %{identity => normalize_id(id)},
           preloads: [relationship],
           select: read_select(resource, model, authority, fields)
         ) do
      {:ok, model} ->
        json(conn, 200, Document.related_document(model, relationship_name, authority: authority, fields: fields))

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  defp direct_to_many_association?(%Ecto.Association.Has{cardinality: :many}), do: true
  defp direct_to_many_association?(_association), do: false

  defp render_to_many_relationship(%{} = request) do
    %{conn: conn, resource: resource, model: model, id: id, authority: authority} = request

    case fetch_parent(resource, model, id, authority, request_context(conn)) do
      {:ok, parent} ->
        request = Map.put(request, :parent, parent)
        related = load_to_many_related(request, :linkage, %{})
        json(conn, 200, linkage_document(parent, model, request.relationship_name, related))

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  defp render_to_many_related(%{} = request) do
    %{conn: conn, resource: resource, model: model, id: id, relationship: relationship} = request
    %{authority: authority, fields: fields} = request

    case fetch_parent(resource, model, id, authority, request_context(conn)) do
      {:ok, parent} ->
        related = request |> Map.put(:parent, parent) |> load_to_many_related(:resource, fields)

        document_opts =
          [
            authority: authority,
            context: request_context(conn),
            page: related.page,
            fields: fields,
            links: true,
            self: related_collection_path(model, relationship)
          ]
          |> maybe_put_related_total_count(related)

        document = Document.document(related.models, document_opts)

        json(conn, 200, document)

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  defp fetch_parent(resource, model, id, authority, context) do
    identity = Hawk.JsonApi.Schema.identity_for_facade(resource)

    resource.one(
      authority: authority,
      context: context,
      filter: %{identity => normalize_id(id)},
      select: read_select(resource, model, authority, %{})
    )
  end

  defp load_to_many_related(%{} = request, mode, fields) do
    %{model: model, reader: reader, parent: parent, relationship: relationship} = request
    %{authority: authority, params: params} = request
    association = model.__schema__(:association, relationship)
    related_reader = related_reader!(reader, model, relationship)
    related_model = association.related
    request_opts = related_request_options(params, related_reader, related_model, authority)
    page = request_opts |> Keyword.get(:page, %{}) |> normalize_related_page(related_reader)
    sort = Keyword.get(request_opts, :sort, related_default_sort(related_reader))
    select = related_select(mode, related_model, authority, fields)

    base_query =
      parent
      |> Ecto.assoc(relationship)
      |> from(as: :root)
      |> related_reader.preload_query(authority)

    query =
      base_query
      |> apply_related_select(select)
      |> apply_related_sort(sort)
      |> apply_related_offset(page)
      |> apply_related_limit(page)

    %{
      models: related_reader.repo().all(query),
      page: page,
      total_count: related_total_count(base_query, related_reader, page)
    }
  end

  defp related_total_count(query, reader, %{total: true}) do
    query
    |> exclude(:order_by)
    |> reader.repo().aggregate(:count, :id)
  end

  defp related_total_count(_query, _reader, _page), do: nil

  defp maybe_put_related_total_count(opts, %{total_count: nil}), do: opts

  defp maybe_put_related_total_count(opts, %{total_count: total_count}),
    do: Keyword.put(opts, :total_count, total_count)

  defp related_request_options(params, reader, model, authority) do
    params
    |> Map.take(["page", "page_number", "page_size", "sort"])
    |> Request.request_options(reader: reader, model: model, authority: authority)
  end

  defp related_reader!(reader, model, relationship) do
    declared_reader =
      if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_readers, 0) do
        Map.get(reader.preload_readers(), relationship)
      end

    declared_reader || association_reader!(model, relationship)
  end

  defp association_reader!(model, relationship) do
    if function_exported?(model, :__hawk_association_reader__, 1) do
      case model.__hawk_association_reader__(relationship) do
        {:ok, reader} -> reader
        :error -> raise ArgumentError, "relationship #{inspect(relationship)} has no Hawk reader"
      end
    else
      raise ArgumentError, "relationship #{inspect(relationship)} has no Hawk reader"
    end
  end

  defp normalize_related_page(page, reader) do
    page
    |> apply_related_default_page_size(reader_default_page_size(reader))
    |> enforce_related_max_page_size!(reader_max_page_size(reader))
  end

  defp reader_default_page_size(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :default_page_size, 0),
      do: reader.default_page_size(),
      else: 100
  end

  defp reader_max_page_size(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :max_page_size, 0),
      do: reader.max_page_size(),
      else: 100
  end

  defp related_default_sort(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :default_sort, 0),
      do: reader.default_sort(),
      else: [asc: :id]
  end

  defp apply_related_default_page_size(%{size: nil} = page, default_page_size),
    do: apply_related_default_page_size(Map.delete(page, :size), default_page_size)

  defp apply_related_default_page_size(page, nil), do: page
  defp apply_related_default_page_size(%{size: _size} = page, _default_page_size), do: page
  defp apply_related_default_page_size(page, default_page_size), do: Map.put(page, :size, default_page_size)

  defp enforce_related_max_page_size!(%{size: nil} = page, _max_page_size), do: page
  defp enforce_related_max_page_size!(page, nil), do: page

  defp enforce_related_max_page_size!(%{size: size} = page, max_page_size)
       when is_integer(size) and is_integer(max_page_size) and size <= max_page_size,
       do: page

  defp enforce_related_max_page_size!(%{size: size}, max_page_size) do
    raise ArgumentError, "page size #{inspect(size)} exceeds maximum #{inspect(max_page_size)}"
  end

  defp related_select(:linkage, model, _authority, _fields), do: [Schema.identity(model)]

  defp related_select(:resource, model, authority, fields) do
    model
    |> Schema.metadata()
    |> then(&Schema.select_fields(model, &1, authority, fields, Schema.identity(model)))
  end

  defp apply_related_select(query, fields), do: select(query, [root: row], struct(row, ^fields))

  defp apply_related_sort(query, sort) do
    Enum.reduce(sort, query, fn {dir, column}, query ->
      order_by(query, [root: row], [{^dir, field(row, ^column)}])
    end)
  end

  defp apply_related_offset(query, page) when not is_map_key(page, :number), do: query
  defp apply_related_offset(query, %{number: nil}), do: query
  defp apply_related_offset(query, %{number: 1}), do: query

  defp apply_related_offset(query, %{number: number, size: size})
       when is_integer(number) and number > 1 and is_integer(size) and size >= 0 do
    offset(query, ^((number - 1) * size))
  end

  defp apply_related_offset(_query, %{number: number}) do
    raise ArgumentError, "page number must be a positive integer, got: #{inspect(number)}"
  end

  defp apply_related_limit(query, %{size: nil}), do: query
  defp apply_related_limit(query, %{size: size}) when is_integer(size) and size >= 0, do: limit(query, ^size)

  defp apply_related_limit(_query, %{size: size}) do
    raise ArgumentError, "page size must be a non-negative integer, got: #{inspect(size)}"
  end

  defp linkage_document(parent, model, relationship_name, related) do
    data =
      Enum.map(related.models, fn model ->
        %{type: Schema.metadata(model).type, id: to_string(Map.get(model, Schema.identity(model)))}
      end)

    page = related_page_meta(related.page, length(data), related.total_count)

    %{
      links: relationship_links(parent, model, relationship_name),
      data: data,
      meta: %{page: page}
    }
  end

  defp related_page_meta(page, count, nil) do
    %{size: Map.get(page, :size), number: Map.get(page, :number, 1), count: count}
  end

  defp related_page_meta(page, count, total_count) do
    page
    |> related_page_meta(count, nil)
    |> Map.put(:total_count, total_count)
  end

  defp relationship_links(parent, model, relationship_name) do
    base = "/" <> Schema.metadata(model).type <> "/" <> to_string(Map.get(parent, Schema.identity(model)))

    %{
      self: base <> "/relationships/" <> relationship_name,
      related: base <> "/" <> relationship_name
    }
  end

  defp related_collection_path(model, relationship) do
    association = model.__schema__(:association, relationship)
    "/" <> Schema.metadata(association.related).type
  end

  defp with_relationship(conn, model, relationship_name, authority, fun) do
    json_api = Schema.metadata(model)

    case Schema.relationship_mapping(json_api, relationship_name) do
      {:ok, {name, source}} ->
        if Schema.visible_field?(json_api, name, authority) do
          fun.(source)
        else
          json(conn, 404, relationship_not_found(relationship_name))
        end

      :error ->
        json(conn, 404, relationship_not_found(relationship_name))
    end
  end

  defp read_select(resource, model, authority, fields) do
    model
    |> Schema.metadata()
    |> then(&Schema.select_fields(model, &1, authority, fields, Schema.identity_for_facade(resource)))
  end

  defp maybe_put_total_count(document_opts, _resource, _opts, %{
         page: %{total: true},
         total_count: total_count
       })
       when is_integer(total_count) do
    Keyword.put(document_opts, :total_count, total_count)
  end

  defp maybe_put_total_count(
         document_opts,
         resource,
         opts,
         %{entries: entries, has_more?: false, page: %{total: true} = page}
       ) do
    total_count =
      if Map.get(page, :number, 1) == 1 and is_nil(Map.get(page, :after)) do
        length(entries)
      else
        resource.count(opts)
      end

    Keyword.put(document_opts, :total_count, total_count)
  end

  defp maybe_put_total_count(document_opts, resource, opts, %{page: %{total: true}}) do
    Keyword.put(document_opts, :total_count, resource.count(opts))
  end

  defp maybe_put_total_count(document_opts, _resource, _opts, _result), do: document_opts

  defp respond_action(conn, resource, action_name, existing, params, authority) do
    if dry_run?(params) do
      respond_action_dry_run(conn, resource, action_name, existing, Map.get(params, "meta", %{}), authority)
    else
      dispatch_action(conn, resource, action_name, existing, Map.get(params, "meta", %{}), authority)
    end
  end

  defp dispatch_action(conn, resource, action_name, existing, meta, authority) do
    case Hawk.Actions.dispatch(resource, action_name, existing, meta, authority) do
      :unknown_action ->
        json(conn, 404, action_not_found(resource, action_name))

      {:ok, results} when is_map(results) and not is_struct(results) ->
        # A two-phase Action returns a map of step name to model. Render the
        # primary resource (the one the action is anchored to) as the JSON:API
        # document; secondary effects are not inlined here.
        primary = primary_result(results, resource.__hawk_resource__(:model))
        respond({:ok, primary}, conn, resource, model_module(existing), 200)

      result ->
        respond(result, conn, resource, model_module(existing), 200)
    end
  end

  defp dry_run?(params) do
    case Map.get(params, "dry-run") do
      nil -> false
      value when value in [true, "true", "1", 1] -> true
      _ -> false
    end
  end

  defp respond_action_dry_run(conn, resource, action_name, existing, meta, authority) do
    actions_module = Hawk.Actions.actions_module(resource)

    with module when is_atom(module) and module != false <- actions_module,
         {:ok, actions} <- fetch_actions(module),
         {:ok, metadata} <- Map.fetch(actions, action_name) do
      change_fn = change_handler_fn(metadata)

      cond do
        function_exported?(module, change_fn, 3) ->
          changesets =
            apply(module, change_fn, [
              existing,
              Hawk.Actions.atomize_params(meta, metadata),
              authority
            ])

          render_dry_run(conn, changesets)

        metadata.build == nil ->
          json(conn, 400, bad_request("action #{inspect(action_name)} is run-only and does not support dry-run"))

        true ->
          json(conn, 404, action_not_found(resource, action_name))
      end
    else
      _ -> json(conn, 404, action_not_found(resource, action_name))
    end
  end

  defp change_handler_fn(%{change_handler: handler}), do: String.to_atom("#{handler}_change")
  defp change_handler_fn(%{handler: handler}), do: String.to_atom("#{handler}_change")

  defp fetch_actions(actions_module) do
    if function_exported?(actions_module, :__hawk_actions__, 0) do
      {:ok, actions_module.__hawk_actions__()}
    else
      :error
    end
  end

  defp render_dry_run(conn, changesets) do
    errors = Enum.flat_map(changesets, &dry_run_errors/1)

    if errors == [],
      do: json(conn, 200, %{data: nil, meta: %{"dry-run": true}}),
      else: json(conn, 422, %{errors: errors})
  end

  defp dry_run_errors({step, changeset}) do
    changeset
    |> Ecto.Changeset.traverse_errors(&error_detail/1)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(
        messages,
        &%{
          status: "422",
          code: "invalid",
          title: "Validation error",
          detail: &1,
          source: %{pointer: "/data/#{step}/#{field}"}
        }
      )
    end)
  end

  defp error_detail({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value), global: false)
    end)
  end

  defp respond({:ok, returned_model}, conn, _resource, _model, status) do
    json(
      conn,
      status,
      Document.document(returned_model,
        context: request_context(conn)
      )
    )
  end

  defp respond(:ok, conn, _resource, _model, status), do: json(conn, status, %{data: nil})

  defp respond({:not_authorized, _context} = result, conn, _resource, _model, _status),
    do: json(conn, 403, Hawk.Errors.to_json_api(result))

  defp respond({:invalid, _context} = result, conn, _resource, _model, _status),
    do: json(conn, 422, Hawk.Errors.to_json_api(result))

  defp respond({:error, _message} = result, conn, _resource, _model, _status),
    do: json(conn, 500, Hawk.Errors.to_json_api(result))

  defp with_error_boundary(conn, fun), do: ControllerSupport.with_error_boundary(conn, fun)
  defp authority!(conn, public?), do: ControllerSupport.authority!(conn, public?)
  defp request_context(conn), do: ControllerSupport.request_context(conn)
  defp json(conn, status, body), do: ControllerSupport.json(conn, status, body)
  defp no_content(conn), do: ControllerSupport.no_content(conn)
  defp bad_request(message), do: ControllerSupport.bad_request(message)

  defp not_found(resource) do
    name =
      resource |> Module.split() |> List.last() |> Macro.underscore() |> String.trim_trailing("s")

    %{
      errors: [
        %{status: "404", code: "not_found", title: "Not found", detail: "#{name} was not found"}
      ]
    }
  end

  defp relationship_not_found(relationship_name) do
    %{
      errors: [
        %{
          status: "404",
          code: "not_found",
          title: "Not found",
          detail: "relationship #{inspect(relationship_name)} was not found"
        }
      ]
    }
  end

  defp action_not_found(resource, action_name) do
    name =
      resource |> Module.split() |> List.last() |> Macro.underscore() |> String.trim_trailing("s")

    %{
      errors: [
        %{
          status: "404",
          code: "action_not_found",
          title: "Not found",
          detail: "#{action_name} is not a supported action for #{name}"
        }
      ]
    }
  end

  defp normalize_id(id), do: Request.validate_uuid!(id)
end

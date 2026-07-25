defmodule Hawk.JsonApi.Controller do
  @moduledoc """
  Phoenix controller helpers for Hawk JSON:API resources.

  Hawk runs behind Phoenix controllers and renders responses through `Plug.Conn`
  directly with the `application/vnd.api+json` content type.
  """

  alias Hawk.JsonApi.Controller, as: JsonApiController
  alias Hawk.JsonApi.{Document, Request, Schema}

  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    model = controller_model!(resource, Keyword.get(opts, :model), env)
    validate_json_api_enabled!(resource)
    public? = Keyword.get(opts, :public, false)
    capabilities = controller_capabilities(resource)

    quote do
      def index(conn, params) do
        JsonApiController.index(
          conn,
          unquote(resource),
          unquote(model),
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

      unquote(quote_writer_actions(resource, model, public?, capabilities))
      unquote(quote_custom_action(resource, model, public?, capabilities))

      def relationship(conn, params) do
        JsonApiController.relationship(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def related(conn, params) do
        JsonApiController.related(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end
    end
  end

  defp controller_capabilities(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) do
      resource.__hawk_resource__(:capabilities)
    else
      %{writer: true, actions: true}
    end
  end

  defp quote_writer_actions(_resource, _model, _public?, %{writer: false}), do: []

  defp quote_writer_actions(resource, model, public?, _capabilities) do
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

  defp quote_custom_action(_resource, _model, _public?, %{actions: false}), do: []

  defp quote_custom_action(resource, model, public?, _capabilities) do
    quote do
      def action(conn, params) do
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

  defp controller_model!(_resource, model, env) when not is_nil(model),
    do: Macro.expand(model, env)

  defp controller_model!(resource, nil, _env) do
    cond do
      Code.ensure_compiled(resource) != {:module, resource} ->
        raise ArgumentError,
              "Hawk JSON:API controller resource #{inspect(resource)} is not available"

      function_exported?(resource, :__hawk_resource__, 1) ->
        resource.__hawk_resource__(:model)

      true ->
        raise ArgumentError,
              "Hawk JSON:API controller requires :model when resource #{inspect(resource)} is not a Hawk.Resource facade"
    end
  end

  defp validate_json_api_enabled!(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) and
         resource.__hawk_resource__(:json_api) == false do
      raise ArgumentError,
            "Hawk JSON:API controller resource #{inspect(resource)} has json_api disabled"
    end
  end

  defp controller_reader(resource) do
    if Code.ensure_compiled(resource) == {:module, resource} and
         function_exported?(resource, :__hawk_resource__, 1) do
      resource.__hawk_resource__(:reader)
    else
      reader = Module.concat(resource, Reader)

      if Code.ensure_compiled(reader) == {:module, reader} do
        reader
      end
    end
  end

  def index(conn, resource, _model, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      fields = Request.sparse_fieldsets(params)

      opts =
        params
        |> Request.request_options(reader: controller_reader(resource))
        |> Keyword.put(:authority, authority)
        |> Keyword.put(:context, request_context(conn))

      document =
        Document.document(resource.all(opts),
          preloads: Keyword.get(opts, :preloads, []),
          context: Keyword.get(opts, :context, %{}),
          page: Keyword.get(opts, :page),
          fields: fields
        )

      json(conn, 200, document)
    end)
  end

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
    case resource.one(authority: authority, context: context, filter: %{id: uuid}) do
      {:ok, model} ->
        json(
          conn,
          200,
          Document.document(model,
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
    case resource.all(
           authority: authority,
           context: context,
           filter: Request.short_id_filter(prefix),
           page: %{size: 2}
         ) do
      [model] ->
        json(
          conn,
          200,
          Document.document(model,
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

  def update(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    do_update(conn, resource, model, id, params, public?)
  end

  defp do_update(conn, resource, model, id, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, existing} ->
          Request.validate_document!(params, model, :updatable)

          params
          |> Request.attributes(model, :updatable)
          |> then(&resource.update(existing, &1, authority))
          |> respond(conn, resource, model, 200)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def delete(conn, resource, _model, %{"id" => id}, public? \\ false) do
    do_delete(conn, resource, id, public?)
  end

  defp do_delete(conn, resource, id, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
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
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, existing} ->
          respond_action(conn, resource, action_name, existing, params, authority)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def relationship(
        conn,
        resource,
        model,
        %{"id" => id, "relationship" => relationship_name},
        public? \\ false
      ) do
    do_relationship(conn, resource, model, id, relationship_name, public?)
  end

  defp do_relationship(conn, resource, model, id, relationship_name, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      relationship = Schema.relationship_key!(model, relationship_name)
      association = model.__schema__(:association, relationship)
      preloads = if match?(%{cardinality: :many}, association), do: [relationship], else: []

      case resource.one(
             authority: authority,
             context: context,
             filter: %{id: normalize_id(id)},
             preloads: preloads
           ) do
        {:ok, loaded} ->
          json(
            conn,
            200,
            Document.relationship_document(loaded, relationship_name)
          )

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def related(
        conn,
        resource,
        model,
        %{"id" => id, "relationship" => relationship_name} = params,
        public? \\ false
      ) do
    do_related(conn, resource, model, id, relationship_name, params, public?)
  end

  defp do_related(conn, resource, model, id, relationship_name, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      fields = Request.sparse_fieldsets(params)

      relationship =
        Schema.relationship_key!(model, relationship_name)

      case resource.one(
             authority: authority,
             context: context,
             filter: %{id: normalize_id(id)},
             preloads: [relationship]
           ) do
        {:ok, model} ->
          json(
            conn,
            200,
            Document.related_document(model, relationship_name, fields: fields)
          )

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  defp respond_action(conn, resource, action_name, existing, params, authority) do
    case Hawk.Actions.dispatch(
           resource,
           action_name,
           existing,
           Map.get(params, "meta", %{}),
           authority
         ) do
      :unknown_action -> json(conn, 404, action_not_found(resource, action_name))
      result -> respond(result, conn, resource, model_module(existing), 200)
    end
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

  defp with_error_boundary(conn, fun) when is_function(fun, 0) do
    fun.()
  rescue
    error in ArgumentError -> json(conn, 400, bad_request(error.message))
  end

  defp bad_request(message) do
    message
    |> Hawk.Error.bad_request()
    |> Hawk.Errors.to_json_api()
  end

  defp authority!(%{assigns: %{authority: authority}}, _public?), do: authority
  defp authority!(_conn, true), do: Hawk.Authority.public()

  defp request_context(conn), do: %{locale: request_locale(conn)}

  defp request_locale(conn) do
    header(conn, "x-locale") || accept_language_locale(header(conn, "accept-language")) || "en"
  end

  defp header(%Plug.Conn{} = conn, name) do
    conn
    |> Plug.Conn.get_req_header(name)
    |> List.first()
  end

  defp accept_language_locale(nil), do: nil

  defp accept_language_locale(header) do
    header
    |> String.split(",")
    |> List.first()
    |> case do
      nil -> nil
      locale -> locale |> String.split(";") |> List.first() |> String.split("-") |> List.first()
    end
  end

  defp json(%Plug.Conn{} = conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/vnd.api+json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp no_content(%Plug.Conn{} = conn), do: Plug.Conn.send_resp(conn, 204, "")

  defp not_found(resource) do
    name =
      resource |> Module.split() |> List.last() |> Macro.underscore() |> String.trim_trailing("s")

    %{
      errors: [
        %{status: "404", code: "not_found", title: "Not found", detail: "#{name} was not found"}
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

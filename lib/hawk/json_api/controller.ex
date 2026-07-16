defmodule Hawk.JsonApi.Controller do
  @moduledoc """
  Phoenix controller helpers for Hawk JSON:API resources.

  Hawk is intended to run behind Phoenix controllers. The generated actions use
  `Phoenix.Controller.json/2` and `Plug.Conn` response helpers when available;
  plain map conns remain supported as a lightweight test boundary.
  """

  alias Hawk.JsonApi
  alias Hawk.JsonApi.Controller, as: JsonApiController

  defmacro __using__(opts) do
    env = __CALLER__
    resource = Keyword.fetch!(opts, :resource) |> Macro.expand(env)
    model = controller_model!(resource, Keyword.get(opts, :model), env)
    public? = Keyword.get(opts, :public, false)

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

      def action(conn, params) do
        JsonApiController.action(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

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

  defp json_api_opts(resource, model),
    do: [json_api_by_model: %{model => json_api_metadata(resource, model)}]

  defp json_api_metadata(resource, model) do
    if function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(:json_api) do
        false -> model.__hawk_json_api__()
        json_api -> json_api.__hawk_json_api__()
      end
    else
      model.__hawk_json_api__()
    end
  end

  def index(conn, resource, model, params, public? \\ false) do
    telemetry_span(conn, resource, model, :index, %{}, fn ->
      with_error_boundary(conn, fn ->
        authority = authority!(conn, public?)

        opts =
          params
          |> JsonApi.request_options()
          |> Keyword.put(:authority, authority)
          |> Keyword.put(:context, request_context(conn))

        json(
          conn,
          200,
          JsonApi.document(resource.all(opts),
            preloads: Keyword.get(opts, :preloads, []),
            context: Keyword.get(opts, :context, %{}),
            page: Keyword.get(opts, :page),
            json_api_by_model: %{model => json_api_metadata(resource, model)}
          )
        )
      end)
    end)
  end

  def show(conn, resource, model, %{"id" => id}, public? \\ false) do
    telemetry_span(conn, resource, model, :show, %{id_kind: id_kind(id)}, fn ->
      do_show(conn, resource, model, id, public?)
    end)
  end

  defp do_show(conn, resource, model, id, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case JsonApi.member_id!(id) do
        {:uuid, uuid} -> show_by_uuid(conn, resource, model, authority, context, uuid)
        {:short_id, prefix} -> show_by_short_id(conn, resource, model, authority, context, prefix)
      end
    end)
  end

  defp show_by_uuid(conn, resource, root_model, authority, context, uuid) do
    case resource.one(authority: authority, context: context, filter: %{id: uuid}) do
      {:ok, model} ->
        json(
          conn,
          200,
          JsonApi.document(model,
            context: request_context(conn),
            links: true,
            json_api_by_model: %{root_model => json_api_metadata(resource, root_model)}
          )
        )

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  defp show_by_short_id(conn, resource, root_model, authority, context, prefix) do
    case resource.all(
           authority: authority,
           context: context,
           filter: JsonApi.short_id_filter(prefix),
           page: %{size: 2}
         ) do
      [model] ->
        json(
          conn,
          200,
          JsonApi.document(model,
            context: request_context(conn),
            links: true,
            json_api_by_model: %{root_model => json_api_metadata(resource, root_model)}
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
    telemetry_span(conn, resource, model, :create, %{}, fn ->
      with_error_boundary(conn, fn ->
        authority = authority!(conn, public?)

        json_api_opts = json_api_opts(resource, model)
        JsonApi.validate_document!(params, model, :creatable, json_api_opts)

        params
        |> JsonApi.attributes(model, :creatable, json_api_opts)
        |> resource.create(authority)
        |> respond(conn, resource, model, 201)
      end)
    end)
  end

  def update(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    telemetry_span(conn, resource, model, :update, %{id_kind: id_kind(id)}, fn ->
      do_update(conn, resource, model, id, params, public?)
    end)
  end

  defp do_update(conn, resource, model, id, params, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, existing} ->
          json_api_opts = json_api_opts(resource, model)
          JsonApi.validate_document!(params, model, :updatable, json_api_opts)

          params
          |> JsonApi.attributes(model, :updatable, json_api_opts)
          |> then(&resource.update(existing, &1, authority))
          |> respond(conn, resource, model, 200)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def delete(conn, resource, model, %{"id" => id}, public? \\ false) do
    telemetry_span(conn, resource, model, :delete, %{id_kind: id_kind(id)}, fn ->
      do_delete(conn, resource, id, public?)
    end)
  end

  defp do_delete(conn, resource, id, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, existing} ->
          existing
          |> resource.delete(authority)
          |> respond(conn, resource, model_module(existing), 200)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def action(
        conn,
        resource,
        model,
        %{"id" => id, "action" => action_name} = params,
        public? \\ false
      ) do
    telemetry_span(conn, resource, model, :action, %{id_kind: id_kind(id)}, fn ->
      do_action(conn, resource, id, action_name, params, public?)
    end)
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
    telemetry_span(conn, resource, model, :relationship, %{id_kind: id_kind(id)}, fn ->
      do_relationship(conn, resource, id, relationship_name, public?)
    end)
  end

  defp do_relationship(conn, resource, id, relationship_name, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, model} -> json(conn, 200, JsonApi.relationship_document(model, relationship_name))
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  def related(
        conn,
        resource,
        model,
        %{"id" => id, "relationship" => relationship_name},
        public? \\ false
      ) do
    telemetry_span(conn, resource, model, :related, %{id_kind: id_kind(id)}, fn ->
      do_related(conn, resource, model, id, relationship_name, public?)
    end)
  end

  defp do_related(conn, resource, model, id, relationship_name, public?) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)
      relationship = JsonApi.relationship_key!(model, relationship_name)

      case resource.one(
             authority: authority,
             context: context,
             filter: %{id: normalize_id(id)},
             preloads: [relationship]
           ) do
        {:ok, model} -> json(conn, 200, JsonApi.related_document(model, relationship_name))
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  defp telemetry_span(_conn, resource, model, action, metadata, fun) when is_function(fun, 0) do
    start_metadata =
      metadata
      |> Map.merge(%{action: action, resource: resource, model: model})
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    :telemetry.span([:hawk, :json_api, :controller, action], start_metadata, fn ->
      conn = fun.()
      {conn, Map.merge(start_metadata, telemetry_stop_metadata(conn))}
    end)
  end

  defp telemetry_stop_metadata(conn) do
    status = Map.get(conn, :status)

    %{
      status: status,
      result: telemetry_result(status)
    }
  end

  defp telemetry_result(status) when status in 200..299, do: :ok
  defp telemetry_result(400), do: :bad_request
  defp telemetry_result(403), do: :not_authorized
  defp telemetry_result(404), do: :not_found
  defp telemetry_result(422), do: :invalid
  defp telemetry_result(status) when is_integer(status) and status >= 500, do: :error
  defp telemetry_result(_status), do: :unknown

  defp id_kind(id) when is_binary(id) do
    cond do
      match?({:ok, _uuid}, Ecto.UUID.cast(id)) -> :uuid
      Regex.match?(~r/\A[0-9a-fA-F]{8}\z/, id) -> :short_id
      true -> :invalid
    end
  end

  defp id_kind(_id), do: :invalid

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

  defp respond({:ok, returned_model}, conn, resource, model, status) do
    json(
      conn,
      status,
      JsonApi.document(returned_model,
        context: request_context(conn),
        json_api_by_model: %{model => json_api_metadata(resource, model)}
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
    %{
      errors: [
        %{status: "400", code: "bad_request", title: "Bad request", detail: message}
      ]
    }
  end

  defp authority!(%{assigns: %{authority: authority}}, _public?), do: authority
  defp authority!(_conn, true), do: Hawk.Authority.public()

  defp request_context(conn), do: %{locale: request_locale(conn)}

  defp request_locale(conn) do
    header(conn, "x-locale") || accept_language_locale(header(conn, "accept-language")) || "en"
  end

  defp header(conn, name) do
    cond do
      plug_conn?(conn) -> plug_conn_header(conn, name)
      is_map(conn) and is_list(Map.get(conn, :req_headers)) -> map_header(conn, name)
      true -> nil
    end
  end

  defp plug_conn?(conn) do
    Code.ensure_loaded?(plug_conn_module()) and
      function_exported?(plug_conn_module(), :get_req_header, 2) and
      is_map(conn) and Map.get(conn, :__struct__) == plug_conn_module()
  end

  defp plug_conn_header(conn, name) do
    plug_conn = plug_conn_module()
    plug_conn.get_req_header(conn, name) |> List.first()
  end

  defp map_header(conn, name) do
    Enum.find_value(conn.req_headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: value
    end)
  end

  defp plug_conn_module, do: Module.concat(["Plug", "Conn"])

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

  defp json(conn, status, body) do
    phoenix_controller = Module.concat([Phoenix, Controller])

    plug_conn = Module.concat([Plug, Conn])

    if Code.ensure_loaded?(phoenix_controller) and
         Code.ensure_loaded?(plug_conn) and
         function_exported?(phoenix_controller, :json, 2) do
      try do
        conn
        |> then(&plug_conn.put_status(&1, status))
        |> put_json_api_content_type(plug_conn)
        |> then(&phoenix_controller.json(&1, body))
      rescue
        FunctionClauseError -> conn |> Map.put(:status, status) |> Map.put(:resp_body, body)
      end
    else
      conn |> Map.put(:status, status) |> Map.put(:resp_body, body)
    end
  end

  defp put_json_api_content_type(%{__struct__: conn_module} = conn, conn_module) do
    conn_module.put_resp_content_type(conn, "application/vnd.api+json")
  end

  defp put_json_api_content_type(conn, _plug_conn), do: conn

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

  defp normalize_id(id), do: JsonApi.validate_uuid!(id)
end

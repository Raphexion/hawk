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
    resource = Keyword.fetch!(opts, :resource)
    model = Keyword.fetch!(opts, :model)
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
    end
  end

  def index(conn, resource, _model, params, public? \\ false) do
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
          page: Keyword.get(opts, :page)
        )
      )
    end)
  end

  def show(conn, resource, _model, %{"id" => id}, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, model} ->
          json(conn, 200, JsonApi.document(model, context: request_context(conn)))

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def create(conn, resource, model, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      params
      |> JsonApi.attributes(model, :creatable)
      |> resource.create(authority)
      |> respond(conn, 201)
    end)
  end

  def update(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, existing} ->
          params
          |> JsonApi.attributes(model, :updatable)
          |> then(&resource.update(existing, &1, authority))
          |> respond(conn, 200)

        :not_found ->
          json(conn, 404, not_found(resource))
      end
    end)
  end

  def delete(conn, resource, _model, %{"id" => id}, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)
      context = request_context(conn)

      case resource.one(authority: authority, context: context, filter: %{id: normalize_id(id)}) do
        {:ok, existing} -> existing |> resource.delete(authority) |> respond(conn, 200)
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  def action(
        conn,
        resource,
        _model,
        %{"id" => id, "action" => action_name} = params,
        public? \\ false
      ) do
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

  defp respond_action(conn, resource, action_name, existing, params, authority) do
    case Hawk.Actions.dispatch(
           resource,
           action_name,
           existing,
           Map.get(params, "meta", %{}),
           authority
         ) do
      :unknown_action -> json(conn, 404, action_not_found(resource, action_name))
      result -> respond(result, conn, 200)
    end
  end

  defp respond({:ok, model}, conn, status),
    do: json(conn, status, JsonApi.document(model, context: request_context(conn)))

  defp respond(:ok, conn, status), do: json(conn, status, %{data: nil})

  defp respond({:not_authorized, _context} = result, conn, _status),
    do: json(conn, 403, Hawk.Errors.to_json_api(result))

  defp respond({:invalid, _context} = result, conn, _status),
    do: json(conn, 422, Hawk.Errors.to_json_api(result))

  defp respond({:error, _message} = result, conn, _status),
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

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _other -> id
    end
  end

  defp normalize_id(id), do: id
end

defmodule Hawk.JsonApi.Controller do
  @moduledoc """
  Phoenix-style controller helpers for Hawk JSON:API resources.

  The generated actions work with Phoenix conns when Phoenix is present and with
  simple `%{assigns: ...}` maps in tests.
  """

  defmacro __using__(opts) do
    resource = Keyword.fetch!(opts, :resource)
    model = Keyword.fetch!(opts, :model)
    public? = Keyword.get(opts, :public, false)

    quote do
      def index(conn, params) do
        Hawk.JsonApi.Controller.index(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def show(conn, params) do
        Hawk.JsonApi.Controller.show(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def create(conn, params) do
        Hawk.JsonApi.Controller.create(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def update(conn, params) do
        Hawk.JsonApi.Controller.update(
          conn,
          unquote(resource),
          unquote(model),
          params,
          unquote(public?)
        )
      end

      def delete(conn, params) do
        Hawk.JsonApi.Controller.delete(
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
      opts = params |> Hawk.JsonApi.request_options() |> Keyword.put(:authority, authority)

      json(
        conn,
        200,
        Hawk.JsonApi.document(resource.all(opts), preloads: Keyword.get(opts, :preloads, []))
      )
    end)
  end

  def show(conn, resource, _model, %{"id" => id}, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
        {:ok, model} -> json(conn, 200, Hawk.JsonApi.document(model))
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  def create(conn, resource, model, params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      params
      |> Hawk.JsonApi.attributes(model, :creatable)
      |> resource.create(authority)
      |> respond(conn, 201)
    end)
  end

  def update(conn, resource, model, %{"id" => id} = params, public? \\ false) do
    with_error_boundary(conn, fn ->
      authority = authority!(conn, public?)

      case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
        {:ok, existing} ->
          params
          |> Hawk.JsonApi.attributes(model, :updatable)
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

      case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
        {:ok, existing} -> existing |> resource.delete(authority) |> respond(conn, 200)
        :not_found -> json(conn, 404, not_found(resource))
      end
    end)
  end

  defp respond({:ok, model}, conn, status), do: json(conn, status, Hawk.JsonApi.document(model))
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

  defp json(conn, status, body) do
    phoenix_controller = Module.concat([Phoenix, Controller])

    plug_conn = Module.concat([Plug, Conn])

    if Code.ensure_loaded?(phoenix_controller) and
         Code.ensure_loaded?(plug_conn) and
         function_exported?(phoenix_controller, :json, 2) do
      try do
        conn
        |> then(&apply(plug_conn, :put_status, [&1, status]))
        |> then(&apply(phoenix_controller, :json, [&1, body]))
      rescue
        FunctionClauseError -> conn |> Map.put(:status, status) |> Map.put(:resp_body, body)
      end
    else
      conn |> Map.put(:status, status) |> Map.put(:resp_body, body)
    end
  end

  defp not_found(resource) do
    name =
      resource |> Module.split() |> List.last() |> Macro.underscore() |> String.trim_trailing("s")

    %{
      errors: [
        %{status: "404", code: "not_found", title: "Not found", detail: "#{name} was not found"}
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

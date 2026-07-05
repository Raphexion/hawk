defmodule Hawk.JsonApi.Controller do
  @moduledoc """
  Phoenix-style controller helpers for Hawk JSON:API resources.

  The generated actions work with Phoenix conns when Phoenix is present and with
  simple `%{assigns: ...}` maps in tests.
  """

  defmacro __using__(opts) do
    resource = Keyword.fetch!(opts, :resource)
    model = Keyword.fetch!(opts, :model)

    quote do
      def index(conn, params) do
        Hawk.JsonApi.Controller.index(conn, unquote(resource), unquote(model), params)
      end

      def show(conn, params) do
        Hawk.JsonApi.Controller.show(conn, unquote(resource), unquote(model), params)
      end

      def create(conn, params) do
        Hawk.JsonApi.Controller.create(conn, unquote(resource), unquote(model), params)
      end

      def update(conn, params) do
        Hawk.JsonApi.Controller.update(conn, unquote(resource), unquote(model), params)
      end

      def delete(conn, params) do
        Hawk.JsonApi.Controller.delete(conn, unquote(resource), unquote(model), params)
      end
    end
  end

  def index(conn, resource, _model, params) do
    authority = authority!(conn)
    opts = params |> Hawk.JsonApi.request_options() |> Keyword.put(:authority, authority)
    json(conn, 200, Hawk.JsonApi.document(resource.all(opts)))
  end

  def show(conn, resource, _model, %{"id" => id}) do
    authority = authority!(conn)

    case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
      {:ok, model} -> json(conn, 200, Hawk.JsonApi.document(model))
      :not_found -> json(conn, 404, not_found(resource))
    end
  end

  def create(conn, resource, model, params) do
    authority = authority!(conn)

    params
    |> Hawk.JsonApi.attributes(model, :creatable)
    |> resource.create(authority)
    |> respond(conn, 201)
  end

  def update(conn, resource, model, %{"id" => id} = params) do
    authority = authority!(conn)

    case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
      {:ok, existing} ->
        params
        |> Hawk.JsonApi.attributes(model, :updatable)
        |> then(&resource.update(existing, &1, authority))
        |> respond(conn, 200)

      :not_found ->
        json(conn, 404, not_found(resource))
    end
  end

  def delete(conn, resource, _model, %{"id" => id}) do
    authority = authority!(conn)

    case resource.one(authority: authority, filter: %{id: normalize_id(id)}) do
      {:ok, existing} -> existing |> resource.delete(authority) |> respond(conn, 200)
      :not_found -> json(conn, 404, not_found(resource))
    end
  end

  defp respond({:ok, model}, conn, status), do: json(conn, status, Hawk.JsonApi.document(model))
  defp respond(:ok, conn, status), do: json(conn, status, %{data: nil})

  defp respond({:not_authorized, _context} = result, conn, _status),
    do: json(conn, 403, Hawk.Errors.to_json_api(result))

  defp respond({:invalid, _context} = result, conn, _status),
    do: json(conn, 422, Hawk.Errors.to_json_api(result))

  defp respond({:error, _message} = result, conn, _status),
    do: json(conn, 500, Hawk.Errors.to_json_api(result))

  defp authority!(%{assigns: %{authority: authority}}), do: authority

  defp json(conn, status, body) do
    phoenix_controller = Module.concat([Phoenix, Controller])

    if Code.ensure_loaded?(phoenix_controller) and
         function_exported?(phoenix_controller, :json, 2) do
      plug_conn = Module.concat([Plug, Conn])

      conn
      |> then(&apply(plug_conn, :put_status, [&1, status]))
      |> then(&apply(phoenix_controller, :json, [&1, body]))
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

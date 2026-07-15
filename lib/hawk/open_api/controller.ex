defmodule Hawk.OpenApi.Controller do
  @moduledoc """
  Phoenix controller helper for serving a composed Hawk OpenAPI specification.

  Example:

      defmodule MyAppWeb.OpenApiController do
        use Hawk.OpenApi.Controller,
          title: "My API",
          version: "1.0.0",
          resources: [MyApp.Course, MyApp.Grade]
      end
  """

  alias Hawk.OpenApi
  alias Hawk.OpenApi.Controller, as: OpenApiController

  defmacro __using__(opts) do
    resources = Keyword.fetch!(opts, :resources)
    spec_opts = Keyword.take(opts, [:title, :version, :path_prefix])

    quote do
      def spec do
        OpenApi.spec(unquote(resources), unquote(spec_opts))
      end

      def show(conn, _params) do
        OpenApiController.show(conn, spec())
      end
    end
  end

  def show(conn, spec), do: json(conn, 200, spec)

  defp json(conn, status, body) do
    phoenix_controller = Module.concat([Phoenix, Controller])

    if Code.ensure_loaded?(phoenix_controller) and
         function_exported?(phoenix_controller, :json, 2) do
      plug_conn = Module.concat([Plug, Conn])

      conn
      |> then(&plug_conn.put_status(&1, status))
      |> then(&phoenix_controller.json(&1, body))
    else
      conn |> Map.put(:status, status) |> Map.put(:resp_body, body)
    end
  end
end

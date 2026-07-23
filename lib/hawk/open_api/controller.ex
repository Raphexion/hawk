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

  defp json(%Plug.Conn{} = conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/vnd.api+json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end

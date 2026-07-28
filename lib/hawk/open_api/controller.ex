defmodule Hawk.OpenApi.Controller do
  @moduledoc """
  Phoenix controller helper for serving a composed Hawk OpenAPI specification.

  `:title` is required — Hawk does not name the host app's API. `:license` is the
  host application's choice; Hawk does not pick one. Accepts a name string or a
  `%{name: ..., url: ...}` map; omit it to leave `info.license` out of the spec.

  Example:

      defmodule MyAppWeb.OpenApiController do
        use Hawk.OpenApi.Controller,
          title: "My API",
          version: "1.0.0",
          resources: [MyApp.Courses, MyApp.Grades],
          license: %{name: "Apache-2.0", url: "https://www.apache.org/licenses/LICENSE-2.0"}
      end
  """

  alias Hawk.OpenApi
  alias Hawk.OpenApi.Controller, as: OpenApiController

  defmacro __using__(opts) do
    resources = Keyword.fetch!(opts, :resources)
    spec_opts = Keyword.take(opts, [:title, :version, :path_prefix, :license])

    quote do
      def spec do
        OpenApi.spec(unquote(resources), unquote(spec_opts))
      end

      def show(conn, _params) do
        OpenApiController.show(conn, spec())
      end
    end
  end

  @doc """
  Renders a composed OpenAPI spec as JSON:API content on the given conn.
  """
  def show(conn, spec), do: json(conn, 200, spec)

  defp json(%Plug.Conn{} = conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/vnd.api+json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end

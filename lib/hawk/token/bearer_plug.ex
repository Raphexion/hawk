defmodule Hawk.Token.BearerPlug do
  @moduledoc """
  Resolves an OAuth-style Bearer access token into `:hawk_authority`.

  Pass `required: true` for protected pipelines. Invalid and missing tokens
  intentionally produce the same response to avoid leaking token state.
  """

  import Plug.Conn

  alias Hawk.Authority

  def init(opts), do: opts

  def call(conn, opts) do
    case bearer_token(conn) do
      nil -> handle_missing(conn, opts)
      token -> handle_verification(conn, token, opts)
    end
  end

  defp handle_verification(conn, token, opts) do
    verifier = Keyword.get(opts, :verifier) || raise ArgumentError, "Hawk.Token.BearerPlug requires :verifier"

    case invoke(verifier, token, opts) do
      {:ok, %Authority{} = authority} -> assign(conn, Keyword.get(opts, :assign, :hawk_authority), authority)
      _ -> handle_invalid(conn, opts)
    end
  end

  defp handle_missing(conn, opts) do
    if Keyword.get(opts, :required, false), do: unauthorized(conn), else: conn
  end

  defp handle_invalid(conn, opts) do
    if Keyword.get(opts, :required, false), do: unauthorized(conn), else: conn
  end

  defp invoke(verifier, token, _opts) when is_function(verifier, 1), do: verifier.(token)
  defp invoke(verifier, token, opts) when is_function(verifier, 2), do: verifier.(token, opts)

  defp invoke({module, function}, token, opts),
    do: apply(module, function, [token, Keyword.get(opts, :verifier_opts, [])])

  defp invoke({module, function, extra}, token, _opts), do: apply(module, function, [token | extra])

  defp unauthorized(conn) do
    body =
      Jason.encode!(%{
        errors: [
          %{status: "401", code: "invalid_token", title: "Unauthorized", detail: "A valid Bearer token is required."}
        ]
      })

    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(401, body)
    |> halt()
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [header] ->
        parse_bearer_header(header)

      _ ->
        nil
    end
  end

  defp parse_bearer_header(header) when is_binary(header) do
    case String.split(String.trim(header), ~r/\s+/, trim: true) do
      [scheme, token] when byte_size(token) > 0 ->
        if String.downcase(scheme) == "bearer", do: token

      _ ->
        nil
    end
  end
end

defmodule Hawk.JsonApi.ControllerSupport do
  @moduledoc false

  alias Hawk.JsonApi.Request

  @json_api_parameters ["ext", "profile"]
  @accept_parameters ["ext", "profile", "q"]

  def with_error_boundary(conn, fun, opts \\ []) when is_function(fun, 0) do
    Request.validate_query_parameter_names!(conn.query_string, Keyword.get(opts, :extra_query_parameters, []))

    case negotiate_media_type(conn) do
      :ok -> fun.()
      {:error, status, body} -> json(conn, status, body)
    end
  rescue
    error in ArgumentError -> json(conn, 400, bad_request(error.message))
  end

  def authority!(%{assigns: %{hawk_authority: authority}}, _public?), do: authority
  def authority!(_conn, true), do: Hawk.Authority.public()

  def request_context(conn), do: %{locale: request_locale(conn)}

  def json(%Plug.Conn{} = conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/vnd.api+json", nil)
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  def no_content(%Plug.Conn{} = conn), do: Plug.Conn.send_resp(conn, 204, "")

  def bad_request(message) do
    message
    |> Hawk.Error.bad_request()
    |> Hawk.Errors.to_json_api()
  end

  defp negotiate_media_type(conn) do
    case validate_content_type(conn) do
      :ok -> validate_accept(conn)
      error -> error
    end
  end

  defp validate_content_type(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [] -> :ok
      [content_type] -> validate_content_type_header(content_type)
      _multiple -> unsupported_media_type_error()
    end
  end

  defp validate_content_type_header(content_type) do
    with {:ok, "application", "vnd.api+json", params} <- Plug.Conn.Utils.media_type(content_type),
         true <- supported_params?(params, @json_api_parameters) do
      :ok
    else
      _unsupported -> unsupported_media_type_error()
    end
  end

  defp unsupported_media_type_error do
    media_type_error(415, :unsupported_media_type, "Unsupported media type")
  end

  defp validate_accept(conn) do
    case Plug.Conn.get_req_header(conn, "accept") do
      [] ->
        :ok

      headers ->
        acceptable? =
          headers
          |> Enum.flat_map(&String.split(&1, ",", trim: true))
          |> Enum.flat_map(&json_api_media_range/1)
          |> accepts_json_api?()

        if acceptable?, do: :ok, else: media_type_error(406, :not_acceptable, "Not acceptable")
    end
  end

  defp json_api_media_range(media_range) do
    case Plug.Conn.Utils.media_type(media_range) do
      {:ok, "*", "*", params} ->
        media_range_quality(params, ["q"], 0)

      {:ok, "application", "*", params} ->
        media_range_quality(params, ["q"], 1)

      {:ok, "application", "vnd.api+json", params} ->
        media_range_quality(params, @accept_parameters, 2)

      _other ->
        []
    end
  end

  defp media_range_quality(params, supported, specificity) do
    with true <- supported_params?(params, supported),
         {:ok, quality} <- quality(params) do
      [{specificity, quality}]
    else
      _unsupported_or_invalid -> []
    end
  end

  defp accepts_json_api?([]), do: false

  defp accepts_json_api?(ranges) do
    highest_specificity = ranges |> Enum.map(&elem(&1, 0)) |> Enum.max()

    ranges
    |> Enum.filter(&(elem(&1, 0) == highest_specificity))
    |> Enum.any?(&(elem(&1, 1) > 0.0))
  end

  defp supported_params?(params, supported) do
    params
    |> Map.keys()
    |> Enum.all?(&Enum.member?(supported, &1))
  end

  defp quality(%{"q" => quality}) do
    case Float.parse(quality) do
      {value, ""} when value >= 0.0 and value <= 1.0 -> {:ok, value}
      _invalid -> :error
    end
  end

  defp quality(_params), do: {:ok, 1.0}

  defp media_type_error(status, code, title) do
    error = %Hawk.Error{status: status, code: code, title: title, detail: title}
    {:error, status, Hawk.Errors.to_json_api(error)}
  end

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
end

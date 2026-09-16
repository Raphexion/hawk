defmodule Hawk.Token.JWT do
  @moduledoc """
  Verifies signed JWT access tokens and maps them to `Hawk.Authority`.

  Required options are `:key`, `:issuer`, `:audience`, and `:roles`. The verifier accepts
  a `JOSE.JWK` key and only permits the configured algorithm (HS256 by default).
  Applications should prefer an asymmetric JWK when tokens are verified by
  more than one service.
  """

  @behaviour Hawk.Token.Verifier

  alias Hawk.Authority

  @default_algorithm "HS256"

  @impl true
  def verify(token, opts) when is_binary(token) and is_list(opts) do
    with {:ok, key} <- fetch_option(opts, :key),
         {:ok, issuer} <- fetch_option(opts, :issuer),
         {:ok, audience} <- fetch_option(opts, :audience),
         {:ok, roles} <- fetch_option(opts, :roles),
         algorithm <- Keyword.get(opts, :algorithm, @default_algorithm),
         {true, jwt, _jws} <- JOSE.JWT.verify_strict(key, [algorithm], token),
         true <- valid_claims?(jwt.fields, issuer, audience),
         {:ok, authority} <- authority(jwt.fields, roles, opts) do
      {:ok, authority}
    else
      _ -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  def verify(_token, _opts), do: {:error, :invalid_token}

  defp authority(claims, roles, opts) when is_list(roles) do
    with sub when is_binary(sub) <- Map.get(claims, "sub"),
         role_name when is_binary(role_name) <- Map.get(claims, Keyword.get(opts, :role_claim, "role")),
         role when is_atom(role) <- role_for(role_name, roles) do
      permissions = claims |> Map.get(Keyword.get(opts, :scope_claim, "scope"), "") |> scopes()
      meta = %{token_id: Map.get(claims, "jti"), issuer: Map.get(claims, "iss")}
      {:ok, Authority.new(role, sub, scopes: %{permissions: permissions}, meta: meta)}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp authority(_claims, _roles, _opts), do: {:error, :invalid_token}

  defp role_for(role_name, roles) do
    Enum.find_value(roles, fn
      {^role_name, role} when is_atom(role) -> role
      role when is_atom(role) -> if Atom.to_string(role) == role_name, do: role
      _ -> nil
    end)
  end

  defp valid_claims?(claims, issuer, audience) do
    now = System.system_time(:second)

    claims["iss"] == issuer and
      audience_match?(claims["aud"], audience) and
      valid_numeric_claim?(claims["iat"], now + 30) and
      valid_numeric_claim?(claims["exp"], now, :future)
  end

  defp valid_numeric_claim?(value, upper_bound, direction \\ :past)
  defp valid_numeric_claim?(value, upper_bound, :past) when is_integer(value), do: value <= upper_bound
  defp valid_numeric_claim?(value, lower_bound, :future) when is_integer(value), do: value > lower_bound
  defp valid_numeric_claim?(_, _, _), do: false

  defp audience_match?(audience, expected) when is_binary(audience), do: audience == expected
  defp audience_match?(audience, expected) when is_list(audience), do: expected in audience
  defp audience_match?(_, _), do: false

  defp scopes(value) when is_binary(value), do: String.split(value, ~r/\s+/, trim: true)
  defp scopes(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp scopes(_), do: []

  defp fetch_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when not is_nil(value) -> {:ok, value}
      _ -> {:error, :missing_option}
    end
  end
end

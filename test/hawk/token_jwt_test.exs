defmodule Hawk.Token.JWTTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Token.JWT

  @key JOSE.JWK.from_oct("test-signing-secret")

  test "verifies a signed token and maps claims to an authority" do
    token = token(%{"sub" => "agent-1", "role" => "teacher", "scope" => "courses:read"})

    assert {:ok, %Authority{} = authority} =
             JWT.verify(token, key: @key, issuer: "https://issuer.example", audience: "hawk-api", roles: [:teacher])

    assert authority.role == :teacher
    assert authority.identity == "agent-1"
    assert authority.scopes == %{permissions: ["courses:read"]}
    assert authority.meta.token_id == "token-1"
  end

  test "rejects wrong issuer, audience, signature, and expired tokens" do
    valid = token(%{})

    opts = [key: @key, issuer: "https://issuer.example", audience: "hawk-api", roles: [:teacher]]
    assert {:error, :invalid_token} = JWT.verify(valid, Keyword.put(opts, :issuer, "wrong"))
    assert {:error, :invalid_token} = JWT.verify(valid, Keyword.put(opts, :audience, "other"))
    assert {:error, :invalid_token} = JWT.verify(valid, Keyword.put(opts, :key, JOSE.JWK.from_oct("wrong")))

    expired = token(%{"exp" => System.system_time(:second) - 10})

    assert {:error, :invalid_token} =
             JWT.verify(expired, key: @key, issuer: "https://issuer.example", audience: "hawk-api", roles: [:teacher])
  end

  test "rejects tokens without required identity and role claims" do
    opts = [key: @key, issuer: "https://issuer.example", audience: "hawk-api", roles: [:teacher]]
    assert {:error, :invalid_token} = JWT.verify(token_without("sub"), opts)
    assert {:error, :invalid_token} = JWT.verify(token_without("role"), opts)
  end

  defp token_without(claim), do: token(%{}) |> then(&remove_claim(&1, claim))

  defp remove_claim(compact, claim) do
    {_, jwt, _jws} = JOSE.JWT.verify_strict(@key, ["HS256"], compact)
    claims = Map.delete(jwt.fields, claim)
    {_, rebuilt} = JOSE.JWT.sign(@key, %JOSE.JWT{fields: claims}) |> JOSE.JWS.compact()
    rebuilt
  end

  defp token(extra) do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => "https://issuer.example",
          "aud" => "hawk-api",
          "sub" => "agent-1",
          "role" => "teacher",
          "iat" => now,
          "exp" => now + 300,
          "jti" => "token-1"
        },
        extra
      )

    {_, token} = JOSE.JWT.sign(@key, %JOSE.JWT{fields: claims}) |> JOSE.JWS.compact()
    token
  end
end

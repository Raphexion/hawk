defmodule Hawk.Token.JWTTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Token.JWT

  @key JOSE.JWK.from_oct("test-signing-secret")
  @opts [key: @key, issuer: "https://issuer.example", audience: "hawk-api", roles: [:teacher]]

  def build_authority(claims, authority, scope_key \\ :school_id) do
    %{authority | identity: {:principal, claims["sub"]}, scopes: %{scope_key => claims["school_id"]}}
  end

  test "supports function and module builders returning an authority directly" do
    for builder <- [&build_authority/2, {__MODULE__, :build_authority}, {__MODULE__, :build_authority, [:tenant_id]}] do
      assert {:ok, authority} =
               JWT.verify(token(%{"school_id" => "school-1"}), Keyword.put(@opts, :authority_builder, builder))

      assert authority.identity == {:principal, "agent-1"}
      assert authority.role == :teacher
      assert authority.meta == %{issuer: "https://issuer.example", token_id: "token-1"}
      assert authority.scopes in [%{school_id: "school-1"}, %{tenant_id: "school-1"}]
    end
  end

  test "builder receives verified claims and the complete default authority exactly once" do
    builder = fn claims, authority ->
      send(self(), {:built, claims, authority})
      {:ok, authority}
    end

    assert {:ok, authority} =
             JWT.verify(
               token(%{"scope" => "courses:read courses:write"}),
               Keyword.put(@opts, :authority_builder, builder)
             )

    assert_received {:built, %{"sub" => "agent-1", "jti" => "token-1"}, ^authority}
    assert authority.scopes == %{permissions: ["courses:read", "courses:write"]}
    refute_received {:built, _, _}
  end

  test "does not invoke builders when signature or required claims are invalid" do
    builder = fn _, authority ->
      send(self(), :builder_called)
      authority
    end

    opts = Keyword.put(@opts, :authority_builder, builder)
    now = System.system_time(:second)

    invalid_tokens = [
      "not-a-jwt",
      token(%{"iss" => "wrong"}),
      token(%{"aud" => "wrong"}),
      token(%{"exp" => now - 60}),
      token(%{"iat" => now + 3600}),
      token_without("sub"),
      token_without("role"),
      token_without("iat"),
      token_without("exp")
    ]

    for invalid <- invalid_tokens do
      assert {:error, :invalid_token} = JWT.verify(invalid, opts)
      refute_received :builder_called
    end

    assert {:error, :invalid_token} = JWT.verify(token(%{}), Keyword.put(opts, :key, JOSE.JWK.from_oct("wrong")))
    refute_received :builder_called
  end

  test "rejects unrecognized roles before invoking the authority builder" do
    builder = fn _, authority ->
      send(self(), :builder_called)
      authority
    end

    result = JWT.verify(token(%{"role" => "unrecognized"}), Keyword.put(@opts, :authority_builder, builder))

    refute_received :builder_called
    assert result == {:error, :invalid_token}
  end

  test "normalizes builder rejection, malformed results, and exceptions to invalid_token" do
    for result <- [{:error, :revoked}, {:ok, %{}}, nil, :invalid] do
      builder = fn _, _ -> result end
      assert {:error, :invalid_token} = JWT.verify(token(%{}), Keyword.put(@opts, :authority_builder, builder))
    end

    builder = fn _, _ -> raise "identity lookup failed" end
    assert {:error, :invalid_token} = JWT.verify(token(%{}), Keyword.put(@opts, :authority_builder, builder))
  end

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

  test "builds a custom authority after verifying the claims" do
    token = token(%{"school_id" => "school-1"})

    assert {:ok, authority} =
             JWT.verify(
               token,
               key: @key,
               issuer: "https://issuer.example",
               audience: "hawk-api",
               roles: [:teacher],
               authority_builder: fn claims, authority ->
                 {:ok, %{authority | scopes: %{school_id: claims["school_id"]}}}
               end
             )

    assert authority.scopes == %{school_id: "school-1"}
  end

  test "rejects a custom authority that is not a Hawk authority" do
    token = token(%{})

    assert {:error, :invalid_token} =
             JWT.verify(
               token,
               key: @key,
               issuer: "https://issuer.example",
               audience: "hawk-api",
               roles: [:teacher],
               authority_builder: fn _claims, _authority -> :invalid end
             )
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

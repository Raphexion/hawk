defmodule Hawk.Token.BearerPlugTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Token.BearerPlug

  test "assigns the verified authority" do
    conn = Plug.Test.conn("get", "/") |> Plug.Conn.put_req_header("authorization", "Bearer good")

    conn =
      BearerPlug.call(conn,
        verifier: fn
          "good" -> {:ok, Authority.new(:agent, "a-1")}
          _ -> {:error, :invalid_token}
        end
      )

    assert conn.assigns.hawk_authority == Authority.new(:agent, "a-1")
    refute conn.halted
  end

  test "accepts case-insensitive Bearer schemes and repeated whitespace" do
    conn = Plug.Test.conn("get", "/") |> Plug.Conn.put_req_header("authorization", "bEaReR   good")

    conn =
      BearerPlug.call(conn,
        verifier: fn
          "good" -> {:ok, Authority.new(:agent, "a-1")}
          _ -> {:error, :invalid_token}
        end
      )

    assert %Authority{identity: "a-1"} = conn.assigns.hawk_authority
  end

  test "does not invoke the verifier for a blank Bearer token" do
    conn = Plug.Test.conn("get", "/") |> Plug.Conn.put_req_header("authorization", "Bearer   ")

    conn =
      BearerPlug.call(conn,
        required: true,
        verifier: fn "" -> raise "blank token must not be verified" end
      )

    assert conn.status == 401
    assert conn.halted
  end

  test "rejects credentials containing whitespace in the token" do
    conn = Plug.Test.conn("get", "/") |> Plug.Conn.put_req_header("authorization", "Bearer good extra")

    conn =
      BearerPlug.call(conn,
        required: true,
        verifier: fn _ -> raise "malformed token must not be verified" end
      )

    assert conn.status == 401
    assert conn.halted
  end

  test "passes verifier_opts to a module verifier" do
    now = System.system_time(:second)
    key = JOSE.JWK.from_oct("secret")

    {_, token} =
      JOSE.JWT.sign(key, %JOSE.JWT{
        fields: %{
          "iss" => "issuer",
          "aud" => "api",
          "sub" => "agent",
          "role" => "agent",
          "iat" => now,
          "exp" => now + 60
        }
      })
      |> JOSE.JWS.compact()

    conn = Plug.Test.conn("get", "/") |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    conn =
      BearerPlug.call(conn,
        verifier: {Hawk.Token.JWT, :verify},
        verifier_opts: [key: JOSE.JWK.from_oct("secret"), issuer: "issuer", audience: "api", roles: [:agent]]
      )

    assert %Authority{role: :agent} = conn.assigns.hawk_authority
  end

  test "required authentication returns a JSON:API 401 response" do
    conn = Plug.Test.conn("get", "/")
    conn = BearerPlug.call(conn, verifier: fn _ -> {:error, :invalid_token} end, required: true)

    assert conn.status == 401
    assert conn.halted
    assert get_in(Jason.decode!(conn.resp_body), ["errors", Access.at(0), "code"]) == "invalid_token"
    assert Plug.Conn.get_resp_header(conn, "www-authenticate") == ["Bearer"]
  end
end

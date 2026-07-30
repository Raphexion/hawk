defmodule Hawk.JsonApiControllerUuidValidationTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiControllerUuidValidationTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Hawk.JsonApiControllerUuidValidationTest.Controller

  @invalid_id "not-a-uuid"
  @system Authority.system()

  test "show rejects invalid UUID path ids before querying" do
    conn = Controller.show(conn(@system), %{"id" => @invalid_id})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID or 8-character short id")
    refute_received {:videdal_repo, :all, _query}
  end

  test "update rejects invalid UUID path ids before querying or validating body" do
    conn = Controller.update(conn(@system), %{"id" => @invalid_id, "data" => %{}})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "delete rejects invalid UUID path ids before querying" do
    conn = Controller.delete(conn(@system), %{"id" => @invalid_id})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "custom actions reject invalid UUID path ids before querying" do
    conn =
      Controller.action(conn(@system), %{
        "id" => @invalid_id,
        "action" => "open-registration",
        "meta" => %{}
      })

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "relationship endpoint rejects invalid UUID path ids before querying" do
    conn = Controller.relationship(conn(@system), %{"id" => @invalid_id, "relationship" => "teacher"})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "related endpoint rejects invalid UUID path ids before querying" do
    conn = Controller.related(conn(@system), %{"id" => @invalid_id, "relationship" => "teacher"})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  defp assert_error(conn, detail) do
    assert %{errors: [%{detail: ^detail}]} = resp(conn)
  end
end

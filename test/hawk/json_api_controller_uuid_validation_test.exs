defmodule Hawk.JsonApiControllerUuidValidationTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiControllerUuidValidationTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiControllerUuidValidationTest.Controller

  @invalid_id "not-a-uuid"

  test "show rejects invalid UUID path ids before querying" do
    conn = Controller.show(conn(), %{"id" => @invalid_id})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "update rejects invalid UUID path ids before querying or validating body" do
    conn = Controller.update(conn(), %{"id" => @invalid_id, "data" => %{}})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "delete rejects invalid UUID path ids before querying" do
    conn = Controller.delete(conn(), %{"id" => @invalid_id})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "custom actions reject invalid UUID path ids before querying" do
    conn =
      Controller.action(conn(), %{
        "id" => @invalid_id,
        "action" => "open-registration",
        "meta" => %{}
      })

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "relationship endpoint rejects invalid UUID path ids before querying" do
    conn = Controller.relationship(conn(), %{"id" => @invalid_id, "relationship" => "teacher"})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  test "related endpoint rejects invalid UUID path ids before querying" do
    conn = Controller.related(conn(), %{"id" => @invalid_id, "relationship" => "teacher"})

    assert conn.status == 400
    assert_error(conn, "id must be a valid UUID")
    refute_received {:videdal_repo, :all, _query}
  end

  defp conn do
    %{
      assigns: %{authority: Hawk.Authority.system()},
      status: nil,
      resp_body: nil
    }
  end

  defp assert_error(conn, detail) do
    assert %{errors: [%{detail: ^detail}]} = conn.resp_body
  end
end

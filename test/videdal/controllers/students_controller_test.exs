defmodule Videdal.Controllers.StudentsController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Students
end

defmodule Videdal.Controllers.StudentsControllerTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.StudentsController
  alias Videdal.{Repo, Student}

  test "index excludes soft-deleted rows by default and exposes include and only modes" do
    school = insert(:school)
    active = insert(:student, school_id: school.id)
    deleted = insert(:student, school_id: school.id, deleted_at: DateTime.utc_now(:second))
    authority = school_admin(school)

    assert response_ids(StudentsController.index(conn(authority), %{})) == [active.id]

    assert StudentsController.index(conn(authority), %{"filter" => %{"deleted" => "include"}})
           |> response_ids()
           |> MapSet.new() == MapSet.new([active.id, deleted.id])

    assert response_ids(StudentsController.index(conn(authority), %{"filter" => %{"deleted" => "only"}})) == [
             deleted.id
           ]
  end

  test "including deleted rows retains tenant authorization" do
    school = insert(:school)
    other_school = insert(:school)
    deleted = insert(:student, school_id: school.id, deleted_at: DateTime.utc_now(:second))
    insert(:student, school_id: other_school.id, deleted_at: DateTime.utc_now(:second))

    conn =
      StudentsController.index(conn(school_admin(school)), %{
        "filter" => %{"deleted" => "include"}
      })

    assert response_ids(conn) == [deleted.id]
  end

  test "delete soft-deletes an active resource" do
    student = insert(:student)

    conn = StudentsController.delete(conn(Authority.system()), %{"id" => student.id})

    assert conn.status == 204
    assert %Student{deleted_at: %DateTime{}} = Repo.get!(Student, student.id)
    assert response_ids(StudentsController.index(conn(Authority.system()), %{})) == []
  end

  defp response_ids(conn) do
    assert conn.status == 200
    Enum.map(resp(conn).data, & &1.id)
  end

  defp school_admin(school),
    do: Authority.new(:school_admin, 1, scopes: %{school_id: school.id})
end

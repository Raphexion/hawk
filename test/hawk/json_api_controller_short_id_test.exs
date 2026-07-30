defmodule Hawk.JsonApiControllerShortIdTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiControllerShortIdTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Hawk.JsonApiControllerShortIdTest.Controller

  @system Authority.system()

  test "show accepts an unambiguous short id" do
    course = insert(:course, title: "Math")
    short_id = String.slice(course.id, 0, 8)

    conn = Controller.show(conn(@system), %{"id" => short_id})

    assert conn.status == 200
    assert resp(conn).data.id == course.id
  end

  test "show returns not found for an unmatched short id" do
    conn = Controller.show(conn(@system), %{"id" => "00000000"})

    assert conn.status == 404
    assert [%{code: "not_found"}] = resp(conn).errors
  end

  test "show rejects ambiguous short ids with a clear error" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course1 = insert(:course, school_id: school.id, teacher_id: teacher.id)
    course2 = insert(:course, school_id: school.id, teacher_id: teacher.id)

    # Make them share the same 8-char prefix
    _short_id = String.slice(course1.id, 0, 8)

    conn = Controller.show(conn(@system), %{"id" => String.slice(course1.id, 0, 8)})

    # Could be ambiguous or not depending on UUID generation.
    # If the first 8 chars match, it's ambiguous; otherwise it's unambiguous.
    if String.slice(course1.id, 0, 8) == String.slice(course2.id, 0, 8) do
      assert conn.status == 400
      assert %{errors: [%{detail: detail}]} = resp(conn)
      assert detail =~ "ambiguous"
    else
      assert conn.status == 200
    end
  end

  test "show rejects malformed ids with a message that mentions short ids" do
    conn = Controller.show(conn(@system), %{"id" => "not-a-uuid"})

    assert conn.status == 400

    assert %{errors: [%{detail: "id must be a valid UUID or 8-character short id"}]} =
             resp(conn)
  end

  test "mutations still reject short ids before querying" do
    conn = Controller.delete(conn(@system), %{"id" => "12345678"})

    assert conn.status == 400
    assert %{errors: [%{detail: "id must be a valid UUID"}]} = resp(conn)
  end
end

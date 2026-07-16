defmodule Hawk.JsonApiControllerShortIdTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiControllerShortIdTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiControllerShortIdTest.Controller
  alias Videdal.Course

  @course_id Videdal.course_id()
  @other_course_id Videdal.other_course_id()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()
  @short_id @course_id |> String.split("-") |> List.first()

  test "show accepts an unambiguous short id" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.show(conn(), %{"id" => @short_id})

    assert conn.status == 200
    assert conn.resp_body.data.id == @course_id
  end

  test "show returns not found for an unmatched short id" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn = Controller.show(conn(), %{"id" => @short_id})

    assert conn.status == 404
    assert [%{code: "not_found"}] = conn.resp_body.errors
  end

  test "show rejects ambiguous short ids with a clear error" do
    courses = [
      %Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id},
      %Course{
        id: @other_course_id,
        title: "Science",
        school_id: @school_id,
        teacher_id: @teacher_id
      }
    ]

    Process.put({Videdal.Repo, :all_results}, courses)

    conn = Controller.show(conn(), %{"id" => @short_id})

    expected_detail = "id prefix #{inspect(@short_id)} is ambiguous"

    assert conn.status == 400
    assert %{errors: [%{detail: ^expected_detail}]} = conn.resp_body
  end

  test "show rejects malformed ids with a message that mentions short ids" do
    conn = Controller.show(conn(), %{"id" => "not-a-uuid"})

    assert conn.status == 400

    assert %{errors: [%{detail: "id must be a valid UUID or 8-character short id"}]} =
             conn.resp_body

    refute_received {:videdal_repo, :all, _query}
  end

  test "mutations still reject short ids before querying" do
    conn = Controller.delete(conn(), %{"id" => @short_id})

    assert conn.status == 400
    assert %{errors: [%{detail: "id must be a valid UUID"}]} = conn.resp_body
    refute_received {:videdal_repo, :all, _query}
  end

  defp conn do
    %{assigns: %{authority: Hawk.Authority.system()}, status: nil, resp_body: nil}
  end
end

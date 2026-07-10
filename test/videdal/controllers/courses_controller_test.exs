defmodule Videdal.Controllers.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Videdal.Controllers.CoursesControllerTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Course
  alias Videdal.Controllers.CoursesController

  @course_id Videdal.course_id()
  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "index returns a JSON:API collection document" do
    courses = [
      %Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}
    ]

    Process.put({Videdal.Repo, :all_results}, courses)

    conn = CoursesController.index(conn(), %{"sort" => "title", "page" => %{"size" => "10"}})

    assert conn.status == 200

    assert conn.resp_body == %{
             data: [
               %{
                 type: "courses",
                 id: @course_id,
                 attributes: %{title: "Math"},
                 relationships: %{
                   school: %{data: %{type: "schools", id: @school_id}},
                   teacher: %{data: %{type: "teachers", id: @teacher_id}},
                   grades: %{data: []}
                 }
               }
             ],
             meta: %{page: %{number: 1, size: 10, count: 1}}
           }

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "order_by: [asc: c0.title]"
    assert inspected =~ "limit: ^10"
  end

  test "show returns one JSON:API resource document" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = CoursesController.show(conn(), %{"id" => @course_id})

    assert conn.status == 200
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.id == @course_id
    assert conn.resp_body.data.attributes == %{title: "Math"}
  end

  test "show returns a JSON:API error when missing" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn = CoursesController.show(conn(), %{"id" => "404"})

    assert conn.status == 404

    assert conn.resp_body == %{
             errors: [
               %{
                 status: "404",
                 code: "not_found",
                 title: "Not found",
                 detail: "course was not found"
               }
             ]
           }
  end

  test "create writes through the resource writer and returns JSON:API" do
    conn =
      CoursesController.create(conn(), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => @school_id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => @teacher_id}}
          }
        }
      })

    assert conn.status == 201
    assert conn.resp_body.data.attributes == %{title: "Math"}
    assert_received {:videdal_repo, :insert, changeset}
    assert changeset.changes == %{title: "Math", school_id: @school_id, teacher_id: @teacher_id}
  end

  test "update returns JSON:API validation errors" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.update(
        conn(%{role: :student, scopes: %{school_id: @school_id, student_id: @student_id}}),
        %{"id" => @course_id, "data" => %{}}
      )

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = conn.resp_body.errors
  end

  defp conn(authority_opts \\ %{role: :school_admin, scopes: %{school_id: @school_id}}) do
    %{assigns: %{authority: authority(authority_opts)}, status: nil, resp_body: nil}
  end

  defp authority(%{role: role, scopes: scopes}),
    do: Authority.new(role, @school_admin_id, scopes: scopes)
end

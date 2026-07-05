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

  test "index returns a JSON:API collection document" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    conn = CoursesController.index(conn(), %{"sort" => "title", "page" => %{"size" => "10"}})

    assert conn.status == 200

    assert conn.resp_body == %{
             data: [
               %{
                 type: "courses",
                 id: "3",
                 attributes: %{title: "Math"},
                 relationships: %{
                   school: %{data: %{type: "schools", id: "7"}},
                   teacher: %{data: %{type: "teachers", id: "12"}},
                   grades: %{data: []}
                 }
               }
             ]
           }

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "order_by: [asc: c0.title]"
    assert inspected =~ "limit: ^10"
  end

  test "show returns one JSON:API resource document" do
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn = CoursesController.show(conn(), %{"id" => "3"})

    assert conn.status == 200
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.id == "3"
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
            "school" => %{"data" => %{"type" => "schools", "id" => "7"}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => "12"}}
          }
        }
      })

    assert conn.status == 201
    assert conn.resp_body.data.attributes == %{title: "Math"}
    assert_received {:videdal_repo, :insert, changeset}
    assert changeset.changes == %{title: "Math", school_id: 7, teacher_id: 12}
  end

  test "update returns JSON:API validation errors" do
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      CoursesController.update(conn(%{role: :student, scopes: %{school_id: 7, student_id: 8}}), %{
        "id" => "3",
        "data" => %{}
      })

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = conn.resp_body.errors
  end

  defp conn(authority_opts \\ %{role: :school_admin, scopes: %{school_id: 7}}) do
    %{assigns: %{authority: authority(authority_opts)}, status: nil, resp_body: nil}
  end

  defp authority(%{role: role, scopes: scopes}), do: Authority.new(role, 1, scopes: scopes)
end

defmodule Hawk.JsonApiRelationshipEndpointTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiRelationshipEndpointTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiRelationshipEndpointTest.Controller
  alias Videdal.{Course, Grade, Teacher}

  test "show documents include self links for resources and relationships" do
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.show(conn(), %{"id" => "3"})

    assert conn.status == 200
    assert conn.resp_body.links.self == "/courses/3"
    assert conn.resp_body.data.links.self == "/courses/3"

    assert conn.resp_body.data.relationships.teacher.links.self ==
             "/courses/3/relationships/teacher"

    assert conn.resp_body.data.relationships.teacher.links.related == "/courses/3/teacher"
  end

  test "relationship endpoint returns relationship linkage" do
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.relationship(conn(), %{"id" => "3", "relationship" => "teacher"})

    assert conn.status == 200

    assert conn.resp_body == %{
             links: %{self: "/courses/3/relationships/teacher", related: "/courses/3/teacher"},
             data: %{type: "teachers", id: "12"}
           }
  end

  test "related endpoint returns the related resource document" do
    teacher = %Teacher{id: 12, name: "Ada", school_id: 7}
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12, teacher: teacher}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.related(conn(), %{"id" => "3", "relationship" => "teacher"})

    assert conn.status == 200
    assert conn.resp_body.links.self == "/teachers/12"
    assert conn.resp_body.data.type == "teachers"
    assert conn.resp_body.data.id == "12"
  end

  test "related endpoint returns collections for to-many relationships" do
    grades = [%Grade{id: 1, score: 12, school_id: 7, student_id: 8, course_id: 3}]
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12, grades: grades}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.related(conn(), %{"id" => "3", "relationship" => "grades"})

    assert conn.status == 200
    assert conn.resp_body.links.self == "/grades"
    assert [%{type: "grades", id: "1"}] = conn.resp_body.data
  end

  test "relationship endpoints reject unknown relationships" do
    hostile = "hawk_hostile_relationship_#{System.unique_integer([:positive])}"
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    Process.put({Videdal.Repo, :all_results}, [course])

    relationship_conn = Controller.relationship(conn(), %{"id" => "3", "relationship" => hostile})
    related_conn = Controller.related(conn(), %{"id" => "3", "relationship" => hostile})
    expected_detail = "unknown relationship #{inspect(hostile)}"

    assert relationship_conn.status == 400
    assert related_conn.status == 400

    assert %{errors: [%{detail: ^expected_detail}]} = relationship_conn.resp_body
    assert %{errors: [%{detail: ^expected_detail}]} = related_conn.resp_body
    assert_raise ArgumentError, fn -> String.to_existing_atom(hostile) end
  end

  defp conn do
    %{assigns: %{authority: Hawk.Authority.system()}, status: nil, resp_body: nil}
  end
end

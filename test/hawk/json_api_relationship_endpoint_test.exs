defmodule Hawk.JsonApiRelationshipEndpointTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiRelationshipEndpointTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.JsonApiRelationshipEndpointTest.Controller
  alias Videdal.{Course, Grade, Teacher}

  @course_id Videdal.course_id()
  @grade_id Videdal.grade_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "show documents include self links for resources and relationships" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.show(conn(Hawk.Authority.system()), %{"id" => @course_id})

    assert conn.status == 200
    body = resp(conn)
    assert body.links.self == "/courses/#{@course_id}"
    assert body.data.links.self == "/courses/#{@course_id}"

    assert body.data.relationships.teacher.links.self ==
             "/courses/#{@course_id}/relationships/teacher"

    assert body.data.relationships.teacher.links.related ==
             "/courses/#{@course_id}/teacher"
  end

  test "relationship endpoint returns relationship linkage" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      Controller.relationship(conn(Hawk.Authority.system()), %{
        "id" => @course_id,
        "relationship" => "teacher"
      })

    assert conn.status == 200

    assert resp(conn) == %{
             links: %{
               self: "/courses/#{@course_id}/relationships/teacher",
               related: "/courses/#{@course_id}/teacher"
             },
             data: %{type: "teachers", id: @teacher_id}
           }
  end

  test "related endpoint returns the related resource document" do
    teacher = %Teacher{id: @teacher_id, name: "Ada", school_id: @school_id}

    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      teacher: teacher
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.related(conn(Hawk.Authority.system()), %{"id" => @course_id, "relationship" => "teacher"})

    assert conn.status == 200
    body = resp(conn)
    assert body.links.self == "/teachers/#{@teacher_id}"
    assert body.data.type == "teachers"
    assert body.data.id == @teacher_id
  end

  test "related endpoint returns collections for to-many relationships" do
    grades = [
      %Grade{
        id: @grade_id,
        score: 12,
        school_id: @school_id,
        student_id: @student_id,
        course_id: @course_id
      }
    ]

    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      grades: grades
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn = Controller.related(conn(Hawk.Authority.system()), %{"id" => @course_id, "relationship" => "grades"})

    assert conn.status == 200
    body = resp(conn)
    assert body.links.self == "/grades"
    assert [%{type: "grades", id: @grade_id}] = body.data
  end

  test "relationship endpoints reject unknown relationships" do
    hostile = "hawk_hostile_relationship_#{System.unique_integer([:positive])}"

    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    relationship_conn =
      Controller.relationship(conn(Hawk.Authority.system()), %{
        "id" => @course_id,
        "relationship" => hostile
      })

    related_conn =
      Controller.related(conn(Hawk.Authority.system()), %{"id" => @course_id, "relationship" => hostile})

    expected_detail = "unknown relationship #{inspect(hostile)}"

    assert relationship_conn.status == 400
    assert related_conn.status == 400

    assert %{errors: [%{detail: ^expected_detail}]} = resp(relationship_conn)
    assert %{errors: [%{detail: ^expected_detail}]} = resp(related_conn)
    assert_raise ArgumentError, fn -> String.to_existing_atom(hostile) end
  end
end

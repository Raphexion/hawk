defmodule Hawk.JsonApiRelationshipEndpointTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiRelationshipEndpointTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Hawk.JsonApiRelationshipEndpointTest.Controller

  test "show documents include self links for resources and relationships" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn = Controller.show(conn(Authority.system()), %{"id" => course.id})

    assert conn.status == 200
    body = resp(conn)
    assert body.links.self == "/courses/#{course.id}"
    assert body.data.links.self == "/courses/#{course.id}"

    assert body.data.relationships.teacher.links.self ==
             "/courses/#{course.id}/relationships/teacher"

    assert body.data.relationships.teacher.links.related ==
             "/courses/#{course.id}/teacher"
  end

  test "relationship endpoint returns relationship linkage" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      Controller.relationship(conn(Authority.system()), %{
        "id" => course.id,
        "relationship" => "teacher"
      })

    assert conn.status == 200

    assert resp(conn) == %{
             links: %{
               self: "/courses/#{course.id}/relationships/teacher",
               related: "/courses/#{course.id}/teacher"
             },
             data: %{type: "teachers", id: teacher.id}
           }
  end

  test "related endpoint returns the related resource document" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id, name: "Ada")
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    conn =
      Controller.related(conn(Authority.system()), %{
        "id" => course.id,
        "relationship" => "teacher"
      })

    assert conn.status == 200
    body = resp(conn)
    assert body.links.self == "/teachers/#{teacher.id}"
    assert body.data.type == "teachers"
    assert body.data.id == teacher.id
  end

  test "related endpoint returns collections for to-many relationships" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    grade =
      insert(:grade,
        school_id: school.id,
        student_id: student.id,
        course_id: course.id,
        score: 12
      )

    conn =
      Controller.related(conn(Authority.system()), %{
        "id" => course.id,
        "relationship" => "grades"
      })

    assert conn.status == 200
    body = resp(conn)
    assert body.links.self == "/grades"
    assert [grade_doc] = body.data
    assert grade_doc.type == "grades"
    assert grade_doc.id == grade.id
  end

  test "relationship endpoints reject unknown relationships" do
    hostile = "hawk_hostile_relationship_#{System.unique_integer([:positive])}"
    course_id = Videdal.course_id()

    relationship_conn =
      Controller.relationship(conn(Authority.system()), %{
        "id" => course_id,
        "relationship" => hostile
      })

    related_conn =
      Controller.related(conn(Authority.system()), %{
        "id" => course_id,
        "relationship" => hostile
      })

    expected_detail = "unknown relationship #{inspect(hostile)}"

    assert relationship_conn.status == 400
    assert related_conn.status == 400

    assert %{errors: [%{detail: ^expected_detail}]} = resp(relationship_conn)
    assert %{errors: [%{detail: ^expected_detail}]} = resp(related_conn)
    assert_raise ArgumentError, fn -> String.to_existing_atom(hostile) end
  end
end

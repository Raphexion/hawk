defmodule Hawk.JsonApiFieldVisibilityTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiFieldVisibilityTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Hawk.JsonApiFieldVisibilityTest.CoursesController

  test "visibility rules only subtract from the declared JSON:API shape" do
    metadata = Videdal.Courses.JsonApi.__hawk_json_api__()

    assert metadata.field_filters == %{public: MapSet.new([:seat_count, :enrollments])}
    assert Map.has_key?(metadata.attributes, :seat_count)
    assert Map.has_key?(metadata.relationships, :enrollments)
  end

  test "public documents hide filtered attributes and relationships" do
    %{course: course} = seed_course(seat_count: 42)

    conn = CoursesController.show(conn(Authority.public()), %{"id" => course.id})

    assert conn.status == 200

    assert resp(conn).data.attributes == %{
             title: "Math",
             registration_state: "draft",
             waitlist_count: 0
           }

    refute Map.has_key?(resp(conn).data.relationships, :enrollments)
  end

  test "callers cannot expand hidden fields with sparse fieldsets" do
    %{course: course} = seed_course(seat_count: 42)

    conn =
      CoursesController.show(conn(Authority.public()), %{
        "id" => course.id,
        "fields" => %{"courses" => "title,seat_count,enrollments,teacher"}
      })

    assert conn.status == 200
    assert resp(conn).data.attributes == %{title: "Math"}
    assert resp(conn).data.relationships.teacher.data == %{type: "teachers", id: course.teacher_id}
    refute Map.has_key?(resp(conn).data.relationships, :enrollments)
  end

  test "visibility rejects options other than hide" do
    assert_raise ArgumentError, ~r/only supports :hide/, fn ->
      Code.compile_string(~S'''
      defmodule Hawk.JsonApiFieldVisibilityTest.InvalidVisibilityOption do
        use Hawk.JsonApi.Resource

        attribute(:title, [])

        visibility do
          role(:public, except: [:title])
        end
      end
      ''')
    end
  end

  test "authorized roles keep the full declared shape" do
    %{course: course} = seed_course(seat_count: 42)

    conn = CoursesController.show(conn(Authority.system()), %{"id" => course.id})

    assert conn.status == 200
    assert resp(conn).data.attributes.seat_count == 42
    assert Map.has_key?(resp(conn).data.relationships, :enrollments)
  end

  test "JSON:API facade projection does not select role-filtered fields but keeps sources needed for visible fields and relationships" do
    fields = Videdal.Courses.json_api_select_fields(Authority.public())

    refute :seat_count in fields
    assert :title in fields
    assert :teacher_id in fields
    assert :school_id in fields
  end

  test "JSON:API facade projection follows sparse fieldsets without letting callers re-add hidden fields" do
    fields =
      Videdal.Courses.json_api_select_fields(Authority.public(), %{
        "courses" => MapSet.new(["title", "seat_count", "teacher"])
      })

    assert fields == [:id, :title, :teacher_id]
  end

  test "role-filtered relationships cannot be included or fetched through relationship endpoints" do
    %{course: course} = seed_course()

    include_conn = CoursesController.index(conn(Authority.public()), %{"include" => "enrollments"})
    assert include_conn.status == 400
    assert hd(resp(include_conn).errors).detail =~ ~s(unknown include "enrollments")

    relationship_conn =
      CoursesController.relationship(conn(Authority.public()), %{
        "id" => course.id,
        "relationship" => "enrollments"
      })

    assert relationship_conn.status == 404
  end

  defp seed_course(attrs \\ []) do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, Keyword.merge([school_id: school.id, teacher_id: teacher.id, title: "Math"], attrs))

    %{school: school, teacher: teacher, course: course}
  end
end

defmodule Videdal.Controllers.AuthenticatedCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Videdal.Controllers.PublicCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course,
    public: true
end

defmodule Hawk.PublicAuthorityTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 0, resp: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.PublicCoursesController

  test "public authority is readonly and not system privileged" do
    authority = Authority.public()

    assert authority.role == :public
    assert authority.identity == :public
    assert Authority.public?(authority)
    assert Authority.readonly?(authority)
    refute Authority.system?(authority)
  end

  test "policy DSL can expose read access to public callers" do
    assert Videdal.Courses.Policy.read_filter(Authority.public()) == :all
  end

  test "public controller actions can read without an assigned authority" do
    insert(:course, title: "Math")

    conn = PublicCoursesController.index(conn(), %{})

    assert conn.status == 200
    [data] = resp(conn).data
    assert data.type == "courses"
    assert data.attributes.title == "Math"
  end

  test "public controller actions still reject writes through readonly authority" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    conn =
      PublicCoursesController.create(conn(), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => school.id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => teacher.id}}
          }
        }
      })

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = resp(conn).errors
  end
end

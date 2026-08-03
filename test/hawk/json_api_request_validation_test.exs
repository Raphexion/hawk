defmodule Hawk.JsonApiRequestValidationTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiRequestValidationTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.JsonApiRequestValidationTest.Controller

  test "create rejects documents without a data object" do
    conn = Controller.create(conn(Hawk.Authority.system()), %{})

    assert conn.status == 400
    assert_error(conn, "request document must include a data object")
  end

  test "create rejects documents with a mismatched resource type" do
    conn =
      Controller.create(conn(Hawk.Authority.system()), %{
        "data" => %{"type" => "grades", "attributes" => %{"title" => "Math"}}
      })

    assert conn.status == 400
    assert_error(conn, "expected data.type to be \"courses\"")
  end

  test "create rejects unknown writable attributes instead of silently ignoring them" do
    conn =
      Controller.create(conn(Hawk.Authority.system()), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math", "secret" => "boom"}
        }
      })

    assert conn.status == 400
    assert_error(conn, "unknown attribute \"secret\"")
  end

  test "create rejects unknown writable relationships instead of silently ignoring them" do
    conn =
      Controller.create(conn(Hawk.Authority.system()), %{
        "data" => %{
          "type" => "courses",
          "relationships" => %{"grades" => %{"data" => []}}
        }
      })

    assert conn.status == 400
    assert_error(conn, "unknown relationship \"grades\"")
  end

  test "create rejects relationship identifiers with the wrong type" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    conn =
      Controller.create(conn(Hawk.Authority.system()), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "teachers", "id" => school.id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => teacher.id}}
          }
        }
      })

    assert conn.status == 400
    assert_error(conn, "expected relationship school type to be \"schools\", got \"teachers\"")
  end

  test "create rejects relationship identifiers that are not UUIDs" do
    teacher = insert(:teacher)

    conn =
      Controller.create(conn(Hawk.Authority.system()), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => "not-a-uuid"}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => teacher.id}}
          }
        }
      })

    assert conn.status == 400
    assert_error(conn, "relationship school id must be a valid UUID")
  end

  test "update requires type and id and rejects a body id that differs from the URL" do
    course = insert(:course)

    missing_type =
      Controller.update(conn(Hawk.Authority.system()), %{
        "id" => course.id,
        "data" => %{"id" => course.id, "attributes" => %{}}
      })

    assert missing_type.status == 400
    assert_error(missing_type, "expected data.type to be \"courses\"")

    missing_id =
      Controller.update(conn(Hawk.Authority.system()), %{
        "id" => course.id,
        "data" => %{"type" => "courses", "attributes" => %{}}
      })

    assert missing_id.status == 400
    assert_error(missing_id, "update data.id is required")

    mismatched_id =
      Controller.update(conn(Hawk.Authority.system()), %{
        "id" => course.id,
        "data" => %{"type" => "courses", "id" => Videdal.other_course_id(), "attributes" => %{}}
      })

    assert mismatched_id.status == 400
    assert_error(mismatched_id, "data.id must match the request path id")
  end

  test "direct update validation accepts its body id as the target and normalizes UUID case" do
    id = Videdal.course_id()
    uppercase_id = String.upcase(id)

    assert :ok =
             Hawk.JsonApi.Request.validate_document!(
               %{"data" => %{"type" => "courses", "id" => uppercase_id}},
               Videdal.Course,
               :updatable
             )

    assert :ok =
             Hawk.JsonApi.Request.validate_document!(
               %{"data" => %{"type" => "courses", "id" => uppercase_id}},
               Videdal.Course,
               :updatable,
               path_id: id
             )
  end

  test "create accepts valid documents" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    conn =
      Controller.create(conn(Hawk.Authority.system()), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => school.id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => teacher.id}}
          }
        }
      })

    assert conn.status == 201
    assert resp(conn).data.type == "courses"
  end

  defp assert_error(conn, detail) do
    assert %{errors: [%{detail: ^detail}]} = resp(conn)
  end
end

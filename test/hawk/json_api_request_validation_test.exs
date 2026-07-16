defmodule Hawk.JsonApiRequestValidationTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiRequestValidationTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiRequestValidationTest.Controller

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "create rejects documents without a data object" do
    conn = Controller.create(conn(), %{})

    assert conn.status == 400
    assert_error(conn, "request document must include a data object")
  end

  test "create rejects documents with a mismatched resource type" do
    conn =
      Controller.create(conn(), %{
        "data" => %{"type" => "grades", "attributes" => %{"title" => "Math"}}
      })

    assert conn.status == 400
    assert_error(conn, "expected data.type to be \"courses\"")
  end

  test "create rejects unknown writable attributes instead of silently ignoring them" do
    conn =
      Controller.create(conn(), %{
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
      Controller.create(conn(), %{
        "data" => %{
          "type" => "courses",
          "relationships" => %{"grades" => %{"data" => []}}
        }
      })

    assert conn.status == 400
    assert_error(conn, "unknown relationship \"grades\"")
  end

  test "create rejects relationship identifiers with the wrong type" do
    conn =
      Controller.create(conn(), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "teachers", "id" => @school_id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => @teacher_id}}
          }
        }
      })

    assert conn.status == 400
    assert_error(conn, "expected relationship school type to be \"schools\", got \"teachers\"")
  end

  test "create rejects relationship identifiers that are not UUIDs" do
    conn =
      Controller.create(conn(), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => "not-a-uuid"}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => @teacher_id}}
          }
        }
      })

    assert conn.status == 400
    assert_error(conn, "relationship school id must be a valid UUID")
  end

  test "create accepts valid documents" do
    conn =
      Controller.create(conn(), %{
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
    assert conn.resp_body.data.type == "courses"
  end

  defp conn do
    %{
      assigns: %{
        authority: Hawk.Authority.new(:school_admin, 1, scopes: %{school_id: @school_id})
      },
      status: nil,
      resp_body: nil
    }
  end

  defp assert_error(conn, detail) do
    assert %{errors: [%{detail: ^detail}]} = conn.resp_body
  end
end

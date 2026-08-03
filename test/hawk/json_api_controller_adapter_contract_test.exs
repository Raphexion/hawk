defmodule Hawk.JsonApiControllerAdapterContractTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.ExternalCoursesController, as: Controller

  @system Authority.system()

  test "controller renders JSON:API adapter contract instead of model metadata" do
    conn = Controller.show(conn(@system), %{"id" => Videdal.course_id()})

    assert conn.status == 200
    body = resp(conn)
    assert body.data.type == "courses"
    assert body.data.attributes == %{name: "Math", slug: "math"}

    assert body.data.relationships.instructor.data == %{
             type: "teachers",
             id: Videdal.teacher_id()
           }

    refute Map.has_key?(body.data.attributes, :title)
    refute Map.has_key?(body.data.attributes, :public_slug)
    refute Map.has_key?(body.data.relationships, :teacher)
  end

  test "relationship endpoint accepts adapter relationship names" do
    conn =
      Controller.relationship(conn(@system), %{
        "id" => Videdal.course_id(),
        "relationship" => "instructor"
      })

    assert conn.status == 200
    body = resp(conn)
    assert body.data == %{type: "teachers", id: Videdal.teacher_id()}
    assert body.links.self == "/courses/#{Videdal.course_id()}/relationships/instructor"
  end

  test "create validates and maps writable adapter attributes and relationships into model attrs" do
    conn =
      Controller.create(
        conn(@system),
        create_params(%{"name" => "Science", "slug" => "science"}, %{
          "instructor" => %{
            "data" => %{"type" => "teachers", "id" => Videdal.teacher_id()}
          }
        })
      )

    assert conn.status == 201
    body = resp(conn)
    assert body.data.type == "courses"
    assert body.data.attributes == %{name: "Science", slug: "science"}

    assert Process.get({Videdal.ExternalCourses.Writer, :create_attrs}) == %{
             title: "Science",
             public_slug: "science",
             teacher_id: Videdal.teacher_id()
           }
  end

  test "update rejects adapter fields that are not updatable" do
    conn =
      Controller.update(
        conn(@system),
        create_params(%{"slug" => "science"})
        |> Map.put("id", Videdal.course_id())
        |> put_in(["data", "id"], Videdal.course_id())
      )

    assert conn.status == 400
    assert [%{detail: "unknown attribute \"slug\""}] = resp(conn).errors
  end

  defp create_params(attributes, relationships \\ %{}) do
    %{
      "data" => %{
        "type" => "courses",
        "attributes" => attributes,
        "relationships" => relationships
      }
    }
  end
end

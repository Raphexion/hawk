defmodule Hawk.JsonApiControllerAdapterContractTest do
  use ExUnit.Case, async: true

  alias Videdal.Controllers.ExternalCoursesController, as: Controller

  test "controller renders JSON:API adapter contract instead of model metadata" do
    conn = Controller.show(conn(), %{"id" => Videdal.course_id()})

    assert conn.status == 200
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.attributes == %{name: "Math", slug: "math"}

    assert conn.resp_body.data.relationships.instructor.data == %{
             type: "internal_teachers",
             id: Videdal.teacher_id()
           }

    refute Map.has_key?(conn.resp_body.data.attributes, :title)
    refute Map.has_key?(conn.resp_body.data.attributes, :public_slug)
    refute Map.has_key?(conn.resp_body.data.relationships, :teacher)
  end

  test "relationship endpoint accepts adapter relationship names" do
    conn =
      Controller.relationship(conn(), %{
        "id" => Videdal.course_id(),
        "relationship" => "instructor"
      })

    assert conn.status == 200
    assert conn.resp_body.data == %{type: "internal_teachers", id: Videdal.teacher_id()}
    assert conn.resp_body.links.self == "/courses/#{Videdal.course_id()}/relationships/instructor"
  end

  test "create validates and maps writable adapter attributes and relationships into model attrs" do
    conn =
      Controller.create(
        conn(),
        create_params(%{"name" => "Science", "slug" => "science"}, %{
          "instructor" => %{
            "data" => %{"type" => "internal_teachers", "id" => Videdal.teacher_id()}
          }
        })
      )

    assert conn.status == 201
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.attributes == %{name: "Science", slug: "science"}

    assert Process.get({Videdal.ExternalCourses.Writer, :create_attrs}) == %{
             title: "Science",
             public_slug: "science",
             teacher_id: Videdal.teacher_id()
           }
  end

  test "update rejects adapter fields that are not updatable" do
    conn =
      Controller.update(
        conn(),
        Map.put(create_params(%{"slug" => "science"}), "id", Videdal.course_id())
      )

    assert conn.status == 400
    assert [%{detail: "unknown attribute \"slug\""}] = conn.resp_body.errors
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

  defp conn do
    %{assigns: %{authority: Hawk.Authority.system()}, status: nil, resp_body: nil}
  end
end

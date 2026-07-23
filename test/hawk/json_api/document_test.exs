defmodule Hawk.JsonApi.DocumentTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Document

  test "renders a collection without a json_api_by_model override, resolving per record" do
    courses = [
      %Videdal.Course{id: "00000000-0000-0000-0000-000000000007", title: "Math", school_id: "7", teacher_id: "12"},
      %Videdal.Course{id: "00000000-0000-0000-0000-000000000012", title: "History", school_id: "7", teacher_id: "12"}
    ]

    document = Document.document(courses, preloads: [:teacher])

    assert Enum.map(document.data, & &1.type) == ["courses", "courses"]
    assert Enum.map(document.data, & &1.id) == ["00000000-0000-0000-0000-000000000007", "00000000-0000-0000-0000-000000000012"]
    assert Enum.map(document.data, & &1.attributes.title) == ["Math", "History"]
  end

  test "renders a single resource without a json_api_by_model override" do
    course = %Videdal.Course{id: "00000000-0000-0000-0000-000000000007", title: "Math", school_id: "7", teacher_id: "12"}

    document = Document.document(course, links: true)

    assert document.data.type == "courses"
    assert document.data.id == "00000000-0000-0000-0000-000000000007"
    assert document.links.self == "/courses/00000000-0000-0000-0000-000000000007"
  end

  test "documents can expose many-to-many relationships without exposing the join schema" do
    student = %Videdal.Student{
      id: Videdal.student_id(),
      name: "Alma",
      active: true,
      school_id: Videdal.school_id(),
      parents: [
        %Videdal.Parent{id: Videdal.parent_id(), name: "Anna", school_id: Videdal.school_id()},
        %Videdal.Parent{
          id: Videdal.other_parent_id(),
          name: "Marcus",
          school_id: Videdal.school_id()
        }
      ]
    }

    document = Document.document(student, preloads: [:parents])

    assert document.data.relationships.parents.data == [
             %{type: "parents", id: Videdal.parent_id()},
             %{type: "parents", id: Videdal.other_parent_id()}
           ]

    refute Map.has_key?(document.data.relationships, :parent_students)
  end
end

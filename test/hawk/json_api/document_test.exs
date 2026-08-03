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

    assert Enum.map(document.data, & &1.id) == [
             "00000000-0000-0000-0000-000000000007",
             "00000000-0000-0000-0000-000000000012"
           ]

    assert Enum.map(document.data, & &1.attributes.title) == ["Math", "History"]
  end

  test "renders sparse fieldsets for attributes and relationships" do
    course = %Videdal.Course{
      id: "00000000-0000-0000-0000-000000000007",
      title: "Math",
      registration_state: "open",
      school_id: "7",
      teacher_id: "12"
    }

    document = Document.document(course, fields: %{"courses" => MapSet.new(["title", "teacher"])})

    assert document.data.attributes == %{title: "Math"}
    assert document.data.relationships == %{teacher: %{data: %{type: "teachers", id: "12"}}}
  end

  test "renders a single resource without a json_api_by_model override" do
    course = %Videdal.Course{
      id: "00000000-0000-0000-0000-000000000007",
      title: "Math",
      school_id: "7",
      teacher_id: "12"
    }

    document = Document.document(course, links: true)

    assert document.data.type == "courses"
    assert document.data.id == "00000000-0000-0000-0000-000000000007"
    assert document.links.self == "/courses/00000000-0000-0000-0000-000000000007"
  end

  test "unloaded to-many relationships are omitted instead of rendered as empty" do
    course = %Videdal.Course{
      id: Videdal.course_id(),
      title: "Math",
      school_id: Videdal.school_id(),
      teacher_id: Videdal.teacher_id()
    }

    without_links = Document.document(course)
    refute Map.has_key?(without_links.data.relationships, :grades)

    with_links = Document.document(course, links: true)
    assert %{links: links} = with_links.data.relationships.grades
    refute Map.has_key?(with_links.data.relationships.grades, :data)
    assert links.related == "/courses/#{course.id}/grades"
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

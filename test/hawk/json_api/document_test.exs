defmodule Hawk.JsonApi.DocumentTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Document

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

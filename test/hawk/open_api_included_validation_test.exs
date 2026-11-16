defmodule Hawk.OpenApiIncludedValidationTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Document
  alias Hawk.Test.NonNullRelationshipPresentation

  setup_all do
    %{
      schema: response_schema(),
      presentation_schema: response_schema(presentation: NonNullRelationshipPresentation)
    }
  end

  test "rendered compound documents validate with multiple known included types", %{schema: schema} do
    document = document()
    assert Enum.sort(Enum.map(document["included"], & &1["type"])) == ["courses", "students"]
    assert {:ok, _} = JSV.validate(document, schema)
  end

  test "known included types cannot use the fallback to evade attribute or linkage constraints", %{schema: schema} do
    for {type, path, invalid} <- [
          {"courses", ["attributes", "title"], 42},
          {"students", ["attributes", "active"], "yes"},
          {"courses", ["relationships", "school", "data"], %{"type" => "teachers", "id" => Ecto.UUID.generate()}},
          {"students", ["relationships", "grades", "data"], nil},
          {"students", ["relationships", "grades", "data"], [%{"type" => "grades"}]}
        ] do
      invalid_document = update_included(document(), type, &put_in(&1, path, invalid))
      assert {:error, %JSV.ValidationError{}} = JSV.validate(invalid_document, schema)
    end
  end

  test "undeclared included types retain the generic resource contract", %{schema: schema} do
    document = document(preloads: [course: [:teacher], student: []])
    assert Enum.any?(document["included"], &(&1["type"] == "teachers"))
    assert {:ok, _} = JSV.validate(document, schema)

    # Unknown attributes stay open, even when their names occur on known types.
    document = update_included(document, "teachers", &Map.put(&1, "attributes", %{"title" => [1, true, nil]}))
    assert {:ok, _} = JSV.validate(document, schema)

    for type <- ["courses", "teachers"],
        corrupt <- [
          &Map.delete(&1, "type"),
          &Map.delete(&1, "id"),
          &Map.put(&1, "type", 42),
          &Map.put(&1, "id", 42),
          &Map.put(&1, "attributes", []),
          &Map.put(&1, "relationships", [])
        ] do
      assert {:error, %JSV.ValidationError{}} =
               document |> update_included(type, corrupt) |> JSV.validate(schema)
    end
  end

  test "sparse fieldsets and empty to-many linkage remain valid", %{schema: schema} do
    fields = %{"courses" => MapSet.new(["title"]), "students" => MapSet.new(["grades"])}
    document = document(fields: fields)
    student = Enum.find(document["included"], &(&1["type"] == "students"))
    assert student["attributes"] == %{}
    assert %{"grades" => %{"data" => []}} = student["relationships"]
    assert {:ok, _} = JSV.validate(document, schema)

    # Sparse/policy projections can omit every declared attribute and relationship.
    document = update_included(document, "courses", &Map.drop(&1, ["attributes", "relationships"]))
    assert {:ok, _} = JSV.validate(document, schema)
  end

  test "included schemas honor the presentation and allow null read linkage", %{presentation_schema: schema} do
    document = document(presentation: NonNullRelationshipPresentation)
    course = Enum.find(document["included"], &(&1["type"] == "courses"))
    assert course["relationships"]["campus"]["data"] == nil
    assert {:ok, _} = JSV.validate(document, schema)

    invalid = %{"type" => "teachers", "id" => Ecto.UUID.generate()}
    document = update_included(document, "courses", &put_in(&1, ["relationships", "campus", "data"], invalid))
    assert {:error, %JSV.ValidationError{}} = JSV.validate(document, schema)
  end

  defp response_schema(opts \\ []) do
    spec = Hawk.OpenApi.spec([Videdal.Grades, Videdal.Courses, Videdal.Students], [title: "Test API"] ++ opts)

    # Validate the serialized response contract, preserving local component refs.
    spec.paths["/grades/{id}"].get.responses["200"].content["application/vnd.api+json"].schema
    |> Map.put(:"$schema", "https://json-schema.org/draft/2020-12/schema")
    |> Map.put(:components, spec.components)
    |> json()
    |> JSV.build!()
  end

  defp document(opts \\ []) do
    teacher = %Videdal.Teacher{id: Ecto.UUID.generate(), name: "Grace"}
    course = %Videdal.Course{id: Ecto.UUID.generate(), title: "Math", teacher_id: teacher.id, teacher: teacher}
    student = %Videdal.Student{id: Ecto.UUID.generate(), name: "Ada", active: true, grades: []}

    grade = %Videdal.Grade{
      id: Ecto.UUID.generate(),
      score: 12,
      course_id: course.id,
      course: course,
      student_id: student.id,
      student: student
    }

    grade
    |> Document.document(Keyword.merge([preloads: [course: [], student: [:grades]], links: true], opts))
    |> json()
  end

  defp update_included(document, type, fun) do
    included =
      Enum.map(document["included"], fn resource ->
        if resource["type"] == type, do: fun.(resource), else: resource
      end)

    Map.put(document, "included", included)
  end

  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()
end

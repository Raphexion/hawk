defmodule Hawk.OpenApiRequiredFieldsTest.ManyFields do
  @fields for index <- 1..40, do: String.to_atom("field_#{index}")

  def adapter(Videdal.Course), do: __MODULE__
  def adapter(_model), do: nil

  def __hawk_json_api__ do
    Videdal.Courses.JsonApi.__hawk_json_api__()
    |> Map.merge(%{
      attributes: Map.new(@fields, &{&1, %{source: :title, required: [:create, :update]}}),
      relationships: Map.new(@fields, &{&1, %{source: :teacher, required: [:create, :update]}}),
      creatable: @fields,
      updatable: @fields
    })
  end
end

defmodule Hawk.OpenApiRequiredFieldsTest.CreateOnly do
  def adapter(Videdal.Course), do: __MODULE__
  def adapter(_model), do: nil

  def __hawk_json_api__ do
    Hawk.OpenApiRequiredFieldsTest.ManyFields.__hawk_json_api__()
    |> Map.update!(
      :attributes,
      &Map.new(&1, fn {name, metadata} ->
        {name, Map.put(metadata, :required, [:create])}
      end)
    )
    |> Map.put(:creatable, [:field_1])
    |> Map.put(:relationships, %{})
  end
end

defmodule Hawk.OpenApiRequiredFieldsTest do
  use ExUnit.Case, async: true

  alias Hawk.OpenApi
  alias Hawk.OpenApiRequiredFieldsTest.ManyFields

  test "create requirements only include writable fields and leave PATCH partial" do
    spec =
      OpenApi.spec([Videdal.Courses],
        title: "Create requirements",
        presentation: Hawk.OpenApiRequiredFieldsTest.CreateOnly
      )

    create = spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema.properties.data
    update = spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema.properties.data

    assert create.required == [:type, :attributes]
    assert create.properties.attributes.required == [:field_1]
    refute Map.has_key?(create.properties.relationships, :required)
    assert update.required == [:type, :id]
    refute Map.has_key?(update.properties.attributes, :required)
    refute Map.has_key?(update.properties.relationships, :required)
  end

  test "required attribute and relationship lists are sorted for create and update" do
    spec = OpenApi.spec([Videdal.Courses], title: "Ordering test", presentation: ManyFields)

    schemas = [
      spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema,
      spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema
    ]

    expected = ManyFields.__hawk_json_api__().attributes |> Map.keys() |> Enum.sort()

    for schema <- schemas do
      assert :attributes in schema.properties.data.required
      assert :relationships in schema.properties.data.required
      assert schema.properties.data.properties.attributes.required == expected
      assert schema.properties.data.properties.relationships.required == expected
    end
  end
end

defmodule Hawk.OpenApiSchemaOverrideTest.Presentation do
  use Hawk.JsonApi.Resource

  type("courses")
  attribute(:title, writable: true, schema: %{enum: ["draft", "published"], maxLength: 20})

  attribute(:settings,
    writable: true,
    nullable: true,
    schema: %{
      type: "object",
      additionalProperties: false,
      properties: %{seats: %{type: "integer", minimum: 1, maximum: 100}}
    }
  )

  relationship(:teacher, writable: true, schema: %{description: "Assigned teacher"})

  def adapter(Videdal.Course), do: __MODULE__
  def adapter(_model), do: nil
end

defmodule Hawk.OpenApiSchemaOverrideTest do
  use ExUnit.Case, async: true

  alias Hawk.OpenApiSchemaOverrideTest.Presentation

  test "DSL overrides appear in response, create, and update schemas" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Overrides", presentation: Presentation)
    response = spec.components.schemas |> Map.fetch!(:CourseResource)
    create = spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema.properties.data
    update = spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema.properties.data

    for schema <- [response, create, update] do
      attributes = schema.properties.attributes.properties
      assert attributes.title == %{type: "string", enum: ["draft", "published"], maxLength: 20}
      assert attributes.settings.type == ["object", "null"]
      assert attributes.settings.additionalProperties == false
      assert attributes.settings.properties.seats == %{type: "integer", minimum: 1, maximum: 100}
      assert schema.properties.relationships.properties.teacher.description == "Assigned teacher"
    end
  end

  test "invalid schema metadata fails at declaration" do
    assert_raise ArgumentError, ~r/:schema must be a map with atom keys/, fn ->
      Code.compile_string("""
      defmodule Hawk.InvalidSchemaOverride do
        use Hawk.JsonApi.Resource
        attribute(:title, schema: [enum: ["draft"]])
      end
      """)
    end
  end
end

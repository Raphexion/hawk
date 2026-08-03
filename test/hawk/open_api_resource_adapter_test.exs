defmodule Hawk.OpenApiResourceAdapterTest do
  use ExUnit.Case, async: true

  test "OpenAPI accepts resource facades and documents adapter JSON:API contract" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses], title: "Test API")

    assert Map.has_key?(spec.paths, "/courses")
    refute Map.has_key?(spec.paths, "/internal_courses")

    course = Map.fetch!(spec.components.schemas, :ExternalCourseResource)

    assert course.description == "External course resource."
    assert course[:"x-resource-type"] == "courses"

    assert course.properties.attributes.properties == %{
             name: %{type: "string", description: "Public course name.", example: "Math"},
             slug: %{type: "string", description: "Public course slug.", example: "math"}
           }

    assert course.properties.relationships.properties.instructor == %{
             type: "object",
             description: "Public instructor relationship.",
             properties: %{
               data: %{
                 anyOf: [
                   %{
                     type: "object",
                     required: [:type, :id],
                     properties: %{
                       id: %{type: "string"},
                       type: %{type: "string", enum: ["teachers"]}
                     }
                   },
                   %{type: "null"}
                 ]
               },
               links: %{"$ref": "#/components/schemas/JsonApiLinks"}
             }
           }
  end

  test "write schemas use adapter names, source types, and capability metadata" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses], title: "Test API")

    create_schema =
      spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema

    update_schema =
      spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema

    assert create_schema.properties.data.properties.attributes.properties == %{
             name: %{type: "string", description: "Public course name.", example: "Math"},
             slug: %{type: "string", description: "Public course slug.", example: "math"}
           }

    assert update_schema.properties.data.properties.attributes.properties == %{
             name: %{type: "string", description: "Public course name.", example: "Math"}
           }

    assert create_schema.properties.data.properties.relationships.properties == %{
             instructor: %{
               type: "object",
               required: [:data],
               description: "Public instructor relationship.",
               properties: %{
                 data: %{
                   anyOf: [
                     %{
                       type: "object",
                       required: [:type, :id],
                       properties: %{
                         id: %{type: "string"},
                         type: %{type: "string", enum: ["teachers"]}
                       }
                     },
                     %{type: "null"}
                   ]
                 }
               }
             }
           }
  end

  test "include parsing resolves external relationship names at every path segment" do
    assert Hawk.JsonApi.Request.request_options(
             %{"include" => "instructor.campus"},
             reader: Videdal.ExternalCourses.Reader,
             model: Videdal.ExternalCourse
           ) == [preloads: [teacher: [:school]]]

    assert_raise ArgumentError, ~r/unknown include "teacher"/, fn ->
      Hawk.JsonApi.Request.request_options(
        %{"include" => "teacher"},
        reader: Videdal.ExternalCourses.Reader,
        model: Videdal.ExternalCourse
      )
    end
  end

  test "include and sort parameters expose adapter names where applicable" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses], title: "Test API")
    parameters = spec.paths["/courses"].get.parameters

    assert %{
             name: "include",
             in: "query",
             schema: %{type: "string", enum: ["instructor", "instructor.campus"]}
           } in parameters

    assert %{
             name: "sort",
             in: "query",
             schema: %{
               type: "string",
               pattern: "^-?(?:public_slug)(?:,-?(?:public_slug))*$"
             },
             description:
               "Comma-separated sort fields. Prefix a field with `-` for descending order. " <>
                 "Allowed fields: public_slug."
           } in parameters
  end

  test "OpenAPI omits resources with json_api disabled" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses, Videdal.InternalNotes], title: "Test API")

    assert Map.has_key?(spec.paths, "/courses")
    refute Map.has_key?(spec.paths, "/internal_notes")
    assert Map.has_key?(spec.components.schemas, :ExternalCourseResource)
    refute Map.has_key?(spec.components.schemas, :InternalNoteResource)
  end

  test "OpenAPI exposes write routes and omits action routes when actions are absent" do
    spec = Hawk.OpenApi.spec([Videdal.CourseCatalog], title: "Test API")

    assert spec.paths["/course-catalog"].get
    assert Map.has_key?(spec.paths["/course-catalog"], :post)

    assert spec.paths["/course-catalog/{id}"].get
    assert Map.has_key?(spec.paths["/course-catalog/{id}"], :patch)
    assert Map.has_key?(spec.paths["/course-catalog/{id}"], :delete)
    refute Map.has_key?(spec.paths, "/course-catalog/{id}/-actions/{action}")

    assert Map.has_key?(spec.paths, "/course-catalog/{id}/relationships/{relationship}")
    assert Map.has_key?(spec.paths, "/course-catalog/{id}/{relationship}")
  end

  test "show id parameter documents short ids; mutations/actions/relationships require full UUIDs" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")

    show_param = hd(spec.paths["/courses/{id}"].get.parameters)
    assert show_param.name == "id"
    assert show_param.schema == %{type: "string"}
    assert show_param[:description] =~ "short id"
    refute Map.has_key?(show_param.schema, :format)

    for {method, path} <- [
          {:patch, "/courses/{id}"},
          {:delete, "/courses/{id}"},
          {:post, "/courses/{id}/-actions/open-registration"},
          {:post, "/courses/{id}/-actions/close-registration"},
          {:get, "/courses/{id}/relationships/{relationship}"},
          {:get, "/courses/{id}/{relationship}"}
        ] do
      id_param = hd(spec.paths[path][method].parameters)
      assert id_param.name == "id"

      assert id_param.schema == %{type: "string", format: "uuid"},
             "expected #{method} #{path} id parameter to require a full UUID"

      refute Map.has_key?(id_param, :description)
    end
  end

  test "spec/2 requires :title" do
    assert_raise ArgumentError, ~r/requires :title/, fn ->
      Hawk.OpenApi.spec([Videdal.ExternalCourses])
    end
  end
end

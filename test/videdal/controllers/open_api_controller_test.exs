defmodule Videdal.Controllers.OpenApiController do
  use Hawk.OpenApi.Controller,
    title: "Videdal API",
    version: "1.0.0",
    path_prefix: "/api/v1",
    resources: [Videdal.Courses, Videdal.Grades]
end

defmodule Videdal.Controllers.OpenApiWithExtrasController do
  use Hawk.OpenApi.Controller,
    title: "Videdal API",
    version: "1.0.0",
    path_prefix: "/api/v1",
    resources: [Videdal.Courses],
    servers: [%{url: "https://api.example.com"}],
    security: [%{"bearerAuth" => []}],
    security_schemes: %{
      bearerAuth: %{type: "http", scheme: "bearer", bearerFormat: "JWT"}
    }
end

defmodule Videdal.Controllers.OpenApiControllerTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 0, resp: 1]

  alias Videdal.Controllers.OpenApiController

  test "serves one OpenAPI document composed from listed Hawk resources" do
    conn = OpenApiController.show(conn(), %{})

    assert conn.status == 200
    assert conn.state == :sent

    spec = OpenApiController.spec()
    assert resp(conn) == Jason.decode!(Jason.encode!(spec), keys: :atoms)
  end

  test "index operations expose JSON:API query parameters from reader and relationships" do
    spec = OpenApiController.spec()
    operation = spec.paths["/api/v1/courses"].get
    parameters = operation.parameters

    assert operation.tags == ["Academics"]
    assert operation[:"x-resource-group"] == "Courses"
    assert operation[:"x-resource-type"] == "courses"

    assert %{
             name: "include",
             in: "query",
             schema: %{
               type: "string",
               enum: [
                 "enrollments",
                 "enrollments.course",
                 "enrollments.school",
                 "enrollments.student",
                 "grades",
                 "grades.course",
                 "grades.student",
                 "school",
                 "teacher",
                 "teacher.campus"
               ]
             }
           } in parameters

    assert %{
             name: "sort",
             in: "query",
             schema: %{
               type: "string",
               pattern: "^-?(?:id|title)(?:,-?(?:id|title))*$"
             },
             description:
               "Comma-separated sort fields. Prefix a field with `-` for descending order. " <>
                 "Allowed fields: id, title."
           } in parameters

    assert %{name: "page[size]", in: "query", schema: %{type: "integer", minimum: 0}} in parameters

    assert %{name: "page[number]", in: "query", schema: %{type: "integer", minimum: 1}} in parameters

    assert %{name: "filter", in: "query"} =
             filter = Enum.find(parameters, &(&1.name == "filter"))

    # Filter is a free-form object; the declared reader filter keys are listed
    # in the description rather than a rigid per-key schema, since JSON:API
    # filter serialization is not standardized and custom handlers may build
    # arbitrary fragments. No style/explode hint: bracket-notation query params
    # have no clean OpenAPI serialization style.
    assert filter.schema == %{type: "object", additionalProperties: true}

    assert Enum.all?(
             ["id", "school_id", "teacher_id", "title", "school_name", "teacher_name"],
             &String.contains?(filter.description, &1)
           )

    assert String.contains?(filter.description, "eq, neq, in, not_in")

    assert %{name: "fields", in: "query"} =
             fields = Enum.find(parameters, &(&1.name == "fields"))

    assert fields.schema == %{type: "object", additionalProperties: %{type: "string"}}
  end

  test "response schemas require mandatory JSON:API document and resource members" do
    spec = OpenApiController.spec()

    collection =
      spec.paths["/api/v1/courses"].get.responses["200"].content["application/vnd.api+json"].schema

    member =
      spec.paths["/api/v1/courses/{id}"].get.responses["200"].content["application/vnd.api+json"].schema

    assert collection.required == [:data]
    assert member.required == [:data]
    assert spec.components.schemas[:CourseResource].required == [:type, :id]
    assert spec.components.schemas[:JsonApiErrorDocument].required == [:errors]
    assert spec.components.schemas[:JsonApiError].required == [:status, :code, :title, :detail]
  end

  test "resource schemas include docs, examples, attributes, and relationships" do
    spec = OpenApiController.spec()
    course = Map.fetch!(spec.components.schemas, :CourseResource)

    assert course.description == "A course taught by a teacher at a school."
    assert course[:"x-resource-group"] == "Courses"
    assert course[:"x-resource-type"] == "courses"

    assert course.properties.attributes.properties.title == %{
             type: "string",
             description: "Human-readable course title.",
             example: "Math"
           }

    assert course.properties.relationships.properties.teacher.description ==
             "The teacher responsible for the course."
  end

  test "write operations use creatable and updatable JSON:API request schemas" do
    spec = OpenApiController.spec()

    create_schema =
      spec.paths["/api/v1/courses"].post.requestBody.content["application/vnd.api+json"].schema

    update_schema =
      spec.paths["/api/v1/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema

    assert create_schema.properties.data.properties.attributes.properties == %{
             title: %{
               type: "string",
               description: "Human-readable course title.",
               example: "Math"
             }
           }

    assert update_schema.properties.data.properties.attributes.properties == %{
             title: %{
               type: "string",
               description: "Human-readable course title.",
               example: "Math"
             }
           }

    assert create_schema.required == [:data]
    assert create_schema.properties.data.required == [:type]
    assert update_schema.required == [:data]
    assert update_schema.properties.data.required == [:type, :id]
    assert update_schema.properties.data.properties.id == %{type: "string", format: "uuid"}
    refute Map.has_key?(create_schema, :additionalProperties)
    refute Map.has_key?(update_schema.properties.data, :additionalProperties)
    assert create_schema.properties.data.properties.attributes.additionalProperties == false
  end

  test "action operations use JSON:API meta request schemas" do
    spec = OpenApiController.spec()

    open_registration = spec.paths["/api/v1/courses/{id}/-actions/open-registration"].post
    close_registration = spec.paths["/api/v1/courses/{id}/-actions/close-registration"].post

    assert open_registration.summary == "Run open-registration for course"

    assert open_registration.description ==
             "Open course registration and configure seats and waitlist capacity."

    assert open_registration.tags == ["Academics"]

    assert open_registration.parameters == [
             %{name: "id", in: "path", required: true, schema: %{type: "string", format: "uuid"}}
           ]

    assert open_registration.responses["200"].content["application/vnd.api+json"].schema == %{
             type: "object",
             required: [:data],
             properties: %{
               data: %{"$ref": "#/components/schemas/CourseResource"}
             }
           }

    assert open_registration.requestBody.content["application/vnd.api+json"].schema == %{
             type: "object",
             required: [:meta],
             properties: %{
               meta: %{
                 type: "object",
                 properties: %{
                   seat_count: %{
                     type: "integer",
                     description: "Seats offered immediately when registration opens.",
                     example: 2
                   },
                   waitlist_count: %{
                     type: "integer",
                     description: "How many waitlist places should be tracked for this course.",
                     example: 1
                   }
                 }
               }
             }
           }

    assert close_registration.summary == "Run close-registration for course"

    assert close_registration.requestBody.content["application/vnd.api+json"].schema == %{
             type: "object",
             required: [:meta],
             properties: %{
               meta: %{
                 type: "object",
                 properties: %{}
               }
             }
           }

    assert Map.keys(open_registration.responses) == ["200", "400", "403", "404", "422"]
    assert open_registration.responses["403"].description == "Forbidden by Hawk policy"
    assert open_registration.responses["422"].description == "Validation failed"
  end

  test "relationship operations describe target types and cardinality" do
    spec = OpenApiController.spec()

    related =
      spec.paths["/api/v1/courses/{id}/{relationship}"].get.responses["200"].content[
        "application/vnd.api+json"
      ].schema

    linkage =
      spec.paths["/api/v1/courses/{id}/relationships/{relationship}"].get.responses["200"].content[
        "application/vnd.api+json"
      ].schema

    assert Enum.any?(related.properties.data.anyOf, &(&1[:type] == "array"))
    assert Enum.any?(related.properties.data.anyOf, &(&1[:type] == "object"))
    assert %{type: "null"} in related.properties.data.anyOf

    assert Enum.any?(linkage.properties.data.anyOf, &(&1[:type] == "array"))
    assert Enum.any?(linkage.properties.data.anyOf, &(&1[:type] == "object"))
    assert %{type: "null"} in linkage.properties.data.anyOf
  end

  test "show and related operations expose sparse fieldsets" do
    spec = OpenApiController.spec()

    show = spec.paths["/api/v1/courses/{id}"].get
    fields = Enum.find(show.parameters, &(&1.name == "fields"))
    assert fields.schema == %{type: "object", additionalProperties: %{type: "string"}}

    # The teacher relationship is a to-one, so its related route exists. The
    # path keeps the generic {relationship} placeholder (one route per
    # resource, the relationship is a path param).
    related = spec.paths["/api/v1/courses/{id}/{relationship}"].get
    related_fields = Enum.find(related.parameters, &(&1.name == "fields"))
    assert related_fields.schema == %{type: "object", additionalProperties: %{type: "string"}}

    # Relationship linkage exposes no sparse fieldsets (it returns identifiers
    # only, not resource attributes).
    relationship = spec.paths["/api/v1/courses/{id}/relationships/{relationship}"].get
    refute Enum.any?(relationship.parameters, &(&1.name == "fields"))
  end

  test ":servers and :security pass through to the spec" do
    spec = Videdal.Controllers.OpenApiWithExtrasController.spec()

    assert spec.servers == [%{url: "https://api.example.com"}]
    assert spec.security == [%{"bearerAuth" => []}]

    assert spec.components.securitySchemes == %{
             bearerAuth: %{type: "http", scheme: "bearer", bearerFormat: "JWT"}
           }
  end

  test "show serves the spec as application/json" do
    conn = Videdal.Controllers.OpenApiController.show(Hawk.TestConn.conn(), %{})

    [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    assert String.starts_with?(content_type, "application/json")
    refute String.contains?(content_type, "vnd.api+json")
  end
end

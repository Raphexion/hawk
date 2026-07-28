defmodule Hawk.JsonApiResourceTest.CourseJsonApi do
  use Hawk.JsonApi.Resource

  type("courses")
  tag("Academics")
  group("Courses")
  doc("A course taught by a teacher.")

  attribute(:title,
    writable: true,
    doc: "Human-readable course title.",
    example: "Math"
  )

  attribute(:slug,
    source: :public_slug,
    creatable: true,
    updatable: false,
    doc: "Stable public slug.",
    example: "math"
  )

  attribute(:display_title,
    resolver: &String.upcase/1,
    doc: "Computed display title."
  )

  relationship(:teacher,
    writable: true,
    doc: "The teacher responsible for the course.",
    example: %{type: "teachers", id: Videdal.teacher_id()}
  )

  relationship(:school,
    creatable: true,
    updatable: false,
    doc: "The school offering the course.",
    example: %{type: "schools", id: Videdal.school_id()}
  )
end

defmodule Hawk.JsonApiResourceTest.EmptyJsonApi do
  use Hawk.JsonApi.Resource
end

defmodule Hawk.JsonApiResourceTest.DescribedTagJsonApi do
  use Hawk.JsonApi.Resource

  type("described-tags")
  tag("Academics", description: "Academic resources.")
end

defmodule Hawk.JsonApiResourceTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiResourceTest.CourseJsonApi
  alias Hawk.JsonApiResourceTest.DescribedTagJsonApi
  alias Hawk.JsonApiResourceTest.EmptyJsonApi

  test "declares explicit JSON:API adapter metadata" do
    assert CourseJsonApi.__hawk_json_api__() == %{
             type: "courses",
             tag: "Academics",
             group: "Courses",
             doc: "A course taught by a teacher.",
             attributes: %{
               title: %{
                 doc: "Human-readable course title.",
                 example: "Math"
               },
               slug: %{
                 source: :public_slug,
                 doc: "Stable public slug.",
                 example: "math"
               },
               display_title: %{
                 resolver: &String.upcase/1,
                 doc: "Computed display title."
               }
             },
             relationships: %{
               teacher: %{
                 doc: "The teacher responsible for the course.",
                 example: %{type: "teachers", id: Videdal.teacher_id()}
               },
               school: %{
                 doc: "The school offering the course.",
                 example: %{type: "schools", id: Videdal.school_id()}
               }
             },
             creatable: [:title, :slug, :teacher, :school],
             updatable: [:title, :teacher]
           }
  end

  test "defaults to an empty adapter contract" do
    assert EmptyJsonApi.__hawk_json_api__() == %{
             attributes: %{},
             relationships: %{},
             creatable: [],
             updatable: []
           }
  end

  test "tag/2 stores the description as a separate metadata key" do
    assert DescribedTagJsonApi.__hawk_json_api__() == %{
             type: "described-tags",
             tag: "Academics",
             tag_description: "Academic resources.",
             attributes: %{},
             relationships: %{},
             creatable: [],
             updatable: []
           }
  end

  test "tag/1 omits the description key" do
    refute Map.has_key?(CourseJsonApi.__hawk_json_api__(), :tag_description)
  end
end

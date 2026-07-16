defmodule Videdal.ExternalCourses.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("courses")
  tag("Academics")
  group("Courses")
  doc("External course resource.")

  attribute(:name,
    source: :title,
    writable: true,
    doc: "Public course name.",
    example: "Math"
  )

  attribute(:slug,
    source: :public_slug,
    creatable: true,
    updatable: false,
    doc: "Public course slug.",
    example: "math"
  )

  relationship(:instructor,
    source: :teacher,
    writable: true,
    doc: "Public instructor relationship."
  )
end

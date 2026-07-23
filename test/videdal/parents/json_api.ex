defmodule Videdal.Parents.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal parents resource.
  """

  use Hawk.JsonApi.Resource

  type("parents")
  doc("A parent or guardian linked to one or more students.")

  attribute(:name,
    writable: true,
    doc: "Parent display name.",
    example: "Ada Parent"
  )

  relationship(:school,
    writable: true,
    doc: "The school this parent belongs to.",
    example: %{type: "schools", id: "7"}
  )

  relationship(:students,
    doc: "Students this parent or guardian can access through internal links.",
    example: [%{type: "students", id: "8"}]
  )
end

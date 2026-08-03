defmodule Videdal.Teachers.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal teachers resource.
  """

  use Hawk.JsonApi.Resource

  type("teachers")
  doc("A teacher who can teach courses and manage grades.")

  attribute(:name,
    writable: true,
    doc: "Teacher display name.",
    example: "Grace Hopper"
  )

  relationship(:campus,
    source: :school,
    writable: true,
    doc: "The school this teacher belongs to.",
    example: %{type: "schools", id: "7"}
  )
end

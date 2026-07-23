defmodule Videdal.Schools.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal schools resource.
  """

  use Hawk.JsonApi.Resource

  type("schools")
  doc("A school in the Videdal example domain.")

  attribute(:name,
    writable: true,
    doc: "Public school name shown to students, parents, and staff.",
    example: "Videdal Skole"
  )
end

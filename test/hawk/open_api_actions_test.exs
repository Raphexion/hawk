defmodule Hawk.OpenApiActionsTest do
  use ExUnit.Case, async: true

  # Videdal.Courses is a full Hawk.Resource facade (reader + writer + policy
  # + actions) — the shape EPI uses. Its `open-registration` action exercises
  # the OpenAPI action-param → JSON schema mapping without a dedicated
  # reader-less test fixture.

  test "OpenAPI action schemas map Hawk action param types to JSON schema types" do
    spec = Hawk.OpenApi.spec([Videdal.Courses])

    action = spec.paths["/courses/{id}/-actions/open-registration"].post
    meta = action.requestBody.content["application/vnd.api+json"].schema.properties.meta

    assert meta.properties == %{
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
  end
end

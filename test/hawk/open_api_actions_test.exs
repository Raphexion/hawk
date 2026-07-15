defmodule Hawk.OpenApiActionsTest.Switch do
  use Hawk.Model

  model "switches" do
    field(:state, :string)
  end

  json_api do
    type("switches")
    doc("A switch that supports custom actions.")
    attribute(:state, doc: "Current state.", example: "off")
    creatable([:state])
    updatable([:state])
  end
end

defmodule Hawk.OpenApiActionsTest.Switches do
end

defmodule Hawk.OpenApiActionsTest.Switches.Actions do
  use Hawk.Actions

  action("toggle",
    params: [
      enabled: [type: :boolean, doc: "Whether the switch should be on.", example: true],
      threshold: [type: :float, doc: "Optional numeric threshold.", example: 0.5],
      label: [type: :string, doc: "Human label for the command.", example: "night mode"]
    ]
  )
end

defmodule Hawk.OpenApiActionsTest do
  use ExUnit.Case, async: true

  test "OpenAPI action schemas map Hawk action param types to JSON schema types" do
    spec = Hawk.OpenApi.spec([Hawk.OpenApiActionsTest.Switch])

    action = spec.paths["/switches/{id}/-actions/toggle"].post
    meta = action.requestBody.content["application/vnd.api+json"].schema.properties.meta

    assert meta.properties == %{
             enabled: %{
               type: "boolean",
               description: "Whether the switch should be on.",
               example: true
             },
             threshold: %{
               type: "number",
               description: "Optional numeric threshold.",
               example: 0.5
             },
             label: %{
               type: "string",
               description: "Human label for the command.",
               example: "night mode"
             }
           }
  end
end

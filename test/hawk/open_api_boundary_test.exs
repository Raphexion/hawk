defmodule Hawk.OpenApiBoundaryTest.BareWidget do
  use Hawk.Model

  model "bare_widgets" do
    field(:name, :string)
  end
end

defmodule Hawk.OpenApiBoundaryTest.BareWidgets.JsonApi do
  use Hawk.JsonApi.Resource

  type("bare_widgets")
  doc("A minimal widget without reader or action modules.")

  attribute(:name,
    writable: true,
    doc: "Widget name.",
    example: "starter"
  )
end

defmodule Hawk.OpenApiBoundaryTest do
  use ExUnit.Case, async: true

  test "OpenAPI falls back cleanly when a resource has no reader or actions modules" do
    spec = Hawk.OpenApi.spec([Hawk.OpenApiBoundaryTest.BareWidget])

    assert spec.paths["/bare_widgets"].get.parameters == [
             %{name: "include", in: "query", schema: %{type: "string", enum: []}},
             %{name: "sort", in: "query", schema: %{type: "string", enum: ["id", "-id"]}},
             %{name: "page[size]", in: "query", schema: %{type: "integer", minimum: 0}}
           ]

    refute Map.has_key?(spec.paths, "/bare_widgets/{id}/-actions/toggle")
    refute Map.has_key?(spec.paths, "/bare_widgets/{id}/-actions")
  end
end

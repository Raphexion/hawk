defmodule Hawk.OpenApiCycleTest.Node do
  use Hawk.Model

  model "nodes" do
    field(:name, :string)
    belongs_to(:parent, Hawk.OpenApiCycleTest.Node)
  end

  json_api do
    type("nodes")
    doc("A self-referential node.")
    attribute(:name, doc: "Node name.", example: "root")
    relationship(:parent, doc: "Parent node.", example: %{type: "nodes", id: "1"})
    creatable([:name, :parent])
    updatable([:name, :parent])
  end
end

defmodule Hawk.OpenApiCycleTest.Nodes do
end

defmodule Hawk.OpenApiCycleTest.Nodes.Reader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Hawk.OpenApiCycleTest.Node,
    policy: Videdal.Courses.Policy

  preload(:parent)
end

defmodule Hawk.OpenApiCycleTest do
  use ExUnit.Case, async: true

  test "OpenAPI include generation stops on self-referential reader cycles" do
    spec = Hawk.OpenApi.spec([Hawk.OpenApiCycleTest.Node])

    include =
      spec.paths["/nodes"].get.parameters
      |> Enum.find(&(&1.name == "include"))

    assert include.schema.enum == ["parent"]
  end
end

defmodule Hawk.OpenApiCycleTest.Node do
  use Hawk.Model

  model "nodes" do
    field(:name, :string)
    belongs_to(:parent, Hawk.OpenApiCycleTest.Node)
  end
end

defmodule Hawk.OpenApiCycleTest.Nodes.JsonApi do
  use Hawk.JsonApi.Resource

  type("nodes")
  doc("A self-referential node.")

  attribute(:name,
    writable: true,
    doc: "Node name.",
    example: "root"
  )

  relationship(:parent,
    writable: true,
    doc: "Parent node.",
    example: %{type: "nodes", id: "1"}
  )
end

defmodule Hawk.OpenApiCycleTest.Nodes.Policy do
  use Hawk.Policy

  @moduledoc false

  read do
    role(:system, :all)
  end
end

defmodule Hawk.OpenApiCycleTest.Nodes.Reader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Hawk.OpenApiCycleTest.Node,
    policy: Hawk.OpenApiCycleTest.Nodes.Policy

  preload(:parent)
end

defmodule Hawk.OpenApiCycleTest.Nodes.Writer do
  @moduledoc false

  def create(attrs, _authority), do: {:ok, struct!(Hawk.OpenApiCycleTest.Node, attrs)}
  def update(model, attrs, _authority), do: {:ok, Map.merge(model, attrs)}
  def delete(_model, _authority), do: :ok
end

defmodule Hawk.OpenApiCycleTest.Nodes do
  use Hawk.Resource,
    model: Hawk.OpenApiCycleTest.Node,
    reader: Hawk.OpenApiCycleTest.Nodes.Reader,
    live_view: false
end

defmodule Hawk.OpenApiCycleTest do
  use ExUnit.Case, async: true

  test "OpenAPI include generation stops on self-referential reader cycles" do
    spec = Hawk.OpenApi.spec([Hawk.OpenApiCycleTest.Nodes], title: "Test API")

    include =
      spec.paths["/nodes"].get.parameters
      |> Enum.find(&(&1.name == "include"))

    assert include.schema.enum == ["parent"]
  end
end

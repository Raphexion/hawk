defmodule Hawk.ResourceContractCaseTest.GoodCourseContractTest do
  use Hawk.ResourceContractCase,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.ResourceContractCaseTest.BadModel do
  use Hawk.Model

  model "bad_models" do
    field(:name, :string)
  end

  json_api do
    type("bad-models")
    attribute(:missing, doc: "This field does not exist.")
    relationship(:ghost, doc: "This association does not exist.")
    creatable([:name, :ghost])
    updatable([:missing])
  end
end

defmodule Hawk.ResourceContractCaseTest.BadResource.Reader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Hawk.ResourceContractCaseTest.BadModel,
    policy: Videdal.Courses.Policy

  filter(:ghost)
  preload(:ghost)
  sort(:ghost)
end

defmodule Hawk.ResourceContractCaseTest.BadResource do
  alias Hawk.ResourceContractCaseTest.BadResource.Reader

  def all(opts), do: Reader.all(opts)
end

defmodule Hawk.ResourceContractCaseTest do
  use ExUnit.Case, async: true

  test "contract validation explains mismatched declarations" do
    assert_raise ArgumentError, ~r/JSON:API attributes must be schema fields: :missing/, fn ->
      Hawk.ResourceContract.validate!(
        Hawk.ResourceContractCaseTest.BadResource,
        Hawk.ResourceContractCaseTest.BadModel
      )
    end
  end
end

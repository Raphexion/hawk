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
end

defmodule Hawk.ResourceContractCaseTest.BadModels.JsonApi do
  use Hawk.JsonApi.Resource

  type("bad-models")

  attribute(:missing,
    updatable: true,
    doc: "This field does not exist."
  )

  attribute(:name, creatable: true)

  relationship(:ghost,
    creatable: true,
    doc: "This association does not exist."
  )
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

defmodule Hawk.ResourceContractCaseTest.MismatchedPolicy do
  use Hawk.Policy

  read do
    role(:school_admin, scopes: [:school_id])
  end
end

defmodule Hawk.ResourceContractCaseTest.MissingRelationshipPreloadResource.Reader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.Courses.Policy

  filter(:id)
end

defmodule Hawk.ResourceContractCaseTest.MissingRelationshipPreloadResource do
  alias Hawk.ResourceContractCaseTest.MissingRelationshipPreloadResource.Reader

  def __hawk_resource__(:reader), do: Reader
  def __hawk_resource__(:policy), do: Videdal.Courses.Policy
  def __hawk_resource__(:json_api), do: Videdal.Courses.JsonApi
end

defmodule Hawk.ResourceContractCaseTest.MismatchedPolicyResource.Reader do
  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Hawk.ResourceContractCaseTest.MismatchedPolicy

  filter(:id)
end

defmodule Hawk.ResourceContractCaseTest.MismatchedPolicyResource do
  alias Hawk.ResourceContractCaseTest.MismatchedPolicyResource.Reader

  def __hawk_resource__(:reader), do: Reader
  def __hawk_resource__(:policy), do: Hawk.ResourceContractCaseTest.MismatchedPolicy
  def __hawk_resource__(:json_api), do: Videdal.Courses.JsonApi

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

  test "contract validation can require JSON:API relationships to be reader preloads" do
    assert_raise ArgumentError,
                 ~r/JSON:API relationships must be declared reader preloads/,
                 fn ->
                   Hawk.ResourceContract.validate!(
                     Hawk.ResourceContractCaseTest.MissingRelationshipPreloadResource,
                     Videdal.Course,
                     require_relationship_preloads: true
                   )
                 end
  end

  test "contract validation catches policy filters missing from the reader" do
    assert_raise ArgumentError,
                 ~r/policy read filters must be declared reader filters: :school_id/,
                 fn ->
                   Hawk.ResourceContract.validate!(
                     Hawk.ResourceContractCaseTest.MismatchedPolicyResource,
                     Videdal.Course
                   )
                 end
  end
end

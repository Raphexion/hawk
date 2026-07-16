defmodule Hawk.JsonApiControllerAdapterContractTest.Course do
  use Hawk.Model

  model "json_api_controller_adapter_contract_courses" do
    field(:title, :string)
    field(:public_slug, :string)
  end

  json_api do
    type("internal_courses")
    attributes([:title, :public_slug])
  end
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.Reader do
  def one(_opts), do: {:ok, sample()}
  def one!(_opts), do: sample()
  def all(_opts), do: [sample()]

  defp sample do
    %Hawk.JsonApiControllerAdapterContractTest.Course{
      id: Videdal.course_id(),
      title: "Math",
      public_slug: "math"
    }
  end
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.JsonApi do
  use Hawk.JsonApi.Resource

  type("courses")
  attribute(:name, source: :title)
  attribute(:slug, source: :public_slug)
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.LiveView do
  def __hawk_live_view__, do: %{surfaces: []}
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses do
  use Hawk.Resource,
    model: Hawk.JsonApiControllerAdapterContractTest.Course,
    writer: false
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Hawk.JsonApiControllerAdapterContractTest.Courses
end

defmodule Hawk.JsonApiControllerAdapterContractTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiControllerAdapterContractTest.Controller

  test "controller renders JSON:API adapter contract instead of model metadata" do
    conn = Controller.show(conn(), %{"id" => Videdal.course_id()})

    assert conn.status == 200
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.attributes == %{name: "Math", slug: "math"}
    refute Map.has_key?(conn.resp_body.data.attributes, :title)
    refute Map.has_key?(conn.resp_body.data.attributes, :public_slug)
  end

  defp conn do
    %{assigns: %{authority: Hawk.Authority.system()}, status: nil, resp_body: nil}
  end
end

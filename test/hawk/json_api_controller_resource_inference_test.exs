defmodule Hawk.JsonApiControllerResourceInferenceTest.Course do
  use Hawk.Model

  model "json_api_controller_resource_inference_courses" do
    field(:title, :string)
  end

  json_api do
    type("courses")
    attribute(:title, example: "Math")
  end
end

defmodule Hawk.JsonApiControllerResourceInferenceTest.Courses.Reader do
  def one(opts),
    do:
      {:ok,
       %Hawk.JsonApiControllerResourceInferenceTest.Course{id: opts[:filter].id, title: "Math"}}

  def one!(_opts), do: raise("not used")

  def all(_opts),
    do: [
      %Hawk.JsonApiControllerResourceInferenceTest.Course{id: Videdal.course_id(), title: "Math"}
    ]
end

defmodule Hawk.JsonApiControllerResourceInferenceTest.Courses.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.JsonApiControllerResourceInferenceTest.Courses.JsonApi do
  def __hawk_json_api__, do: %{type: "courses"}
end

defmodule Hawk.JsonApiControllerResourceInferenceTest.Courses.LiveView do
  def __hawk_live_view__, do: %{surfaces: []}
end

defmodule Hawk.JsonApiControllerResourceInferenceTest.Courses do
  use Hawk.Resource,
    model: Hawk.JsonApiControllerResourceInferenceTest.Course,
    writer: false
end

defmodule Hawk.JsonApiControllerResourceInferenceTest.Controller do
  use Hawk.JsonApi.Controller,
    resource: Hawk.JsonApiControllerResourceInferenceTest.Courses
end

defmodule Hawk.JsonApiControllerResourceInferenceTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiControllerResourceInferenceTest.Controller

  test "controller infers model from Hawk.Resource facade" do
    conn = Controller.index(conn(), %{})

    assert conn.status == 200
    assert [%{type: "courses", id: course_id}] = conn.resp_body.data
    assert course_id == Videdal.course_id()
  end

  test "member actions use the inferred model metadata" do
    conn = Controller.show(conn(), %{"id" => Videdal.course_id()})

    assert conn.status == 200
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.id == Videdal.course_id()
  end

  defp conn do
    %{assigns: %{authority: Hawk.Authority.system()}, status: nil, resp_body: nil}
  end
end

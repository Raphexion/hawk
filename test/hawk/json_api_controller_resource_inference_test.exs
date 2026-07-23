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
    do: {:ok, %Hawk.JsonApiControllerResourceInferenceTest.Course{id: opts[:filter].id, title: "Math"}}

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
  def __hawk_live_view__, do: %{index: %{}, show: %{}}
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

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Hawk.JsonApiControllerResourceInferenceTest.Controller

  @system Authority.system()

  test "controller infers model from Hawk.Resource facade" do
    conn = Controller.index(conn(@system), %{})

    assert conn.status == 200
    assert [%{type: "courses", id: course_id}] = resp(conn).data
    assert course_id == Videdal.course_id()
  end

  test "member actions use the inferred model metadata" do
    conn = Controller.show(conn(@system), %{"id" => Videdal.course_id()})

    assert conn.status == 200
    body = resp(conn)
    assert body.data.type == "courses"
    assert body.data.id == Videdal.course_id()
  end

  test "controller only exposes write actions when writer is enabled" do
    refute function_exported?(Controller, :create, 2)
    refute function_exported?(Controller, :update, 2)
    refute function_exported?(Controller, :delete, 2)
  end

  test "controller only exposes custom action endpoint when actions are enabled" do
    refute function_exported?(Controller, :action, 2)
  end

  test "controller refuses resources with json_api disabled" do
    assert_raise ArgumentError,
                 ~r/Hawk JSON:API controller resource Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabled has json_api disabled/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabled.Reader do
                     def one(_opts), do: :not_found
                     def all(_opts), do: []
                   end

                   defmodule Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabled.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabled.LiveView do
                     def __hawk_live_view__, do: %{index: %{}, show: %{}}
                   end

                   defmodule Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabled do
                     use Hawk.Resource,
                       model: Hawk.JsonApiControllerResourceInferenceTest.Course,
                       writer: false,
                       json_api: false
                   end

                   defmodule Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabledController do
                     use Hawk.JsonApi.Controller,
                       resource: Hawk.JsonApiControllerResourceInferenceTest.JsonApiDisabled
                   end
                   """)
                 end
  end
end

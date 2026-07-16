defmodule Hawk.JsonApiControllerAdapterContractTest.Teacher do
  use Hawk.Model

  model "json_api_controller_adapter_contract_teachers" do
    field(:name, :string)
  end

  json_api do
    type("teachers")
    attributes([:name])
  end
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Course do
  use Hawk.Model

  model "json_api_controller_adapter_contract_courses" do
    field(:title, :string)
    field(:public_slug, :string)
    belongs_to(:teacher, Hawk.JsonApiControllerAdapterContractTest.Teacher)
  end

  json_api do
    type("internal_courses")
    attributes([:title, :public_slug])
    relationships([:teacher])
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
      public_slug: "math",
      teacher_id: Videdal.teacher_id()
    }
  end
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.Writer do
  def create(attrs, _authority) do
    Process.put({__MODULE__, :create_attrs}, attrs)

    {:ok,
     %Hawk.JsonApiControllerAdapterContractTest.Course{
       id: Videdal.course_id(),
       title: Map.fetch!(attrs, :title),
       public_slug: Map.fetch!(attrs, :public_slug),
       teacher_id: Map.fetch!(attrs, :teacher_id)
     }}
  end

  def update(%Hawk.JsonApiControllerAdapterContractTest.Course{} = model, attrs, _authority) do
    Process.put({__MODULE__, :update_attrs}, attrs)

    {:ok,
     %Hawk.JsonApiControllerAdapterContractTest.Course{
       model
       | title: Map.get(attrs, :title, model.title),
         public_slug: Map.get(attrs, :public_slug, model.public_slug)
     }}
  end

  def delete(model, _authority), do: {:ok, model}
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.JsonApi do
  use Hawk.JsonApi.Resource

  type("courses")
  attribute(:name, source: :title, writable: true)
  attribute(:slug, source: :public_slug, creatable: true, updatable: false)
  relationship(:instructor, source: :teacher, writable: true)
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses.LiveView do
  def __hawk_live_view__, do: %{surfaces: []}
end

defmodule Hawk.JsonApiControllerAdapterContractTest.Courses do
  use Hawk.Resource,
    model: Hawk.JsonApiControllerAdapterContractTest.Course
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

    assert conn.resp_body.data.relationships.instructor.data == %{
             type: "teachers",
             id: Videdal.teacher_id()
           }

    refute Map.has_key?(conn.resp_body.data.attributes, :title)
    refute Map.has_key?(conn.resp_body.data.attributes, :public_slug)
    refute Map.has_key?(conn.resp_body.data.relationships, :teacher)
  end

  test "relationship endpoint accepts adapter relationship names" do
    conn =
      Controller.relationship(conn(), %{
        "id" => Videdal.course_id(),
        "relationship" => "instructor"
      })

    assert conn.status == 200
    assert conn.resp_body.data == %{type: "teachers", id: Videdal.teacher_id()}
    assert conn.resp_body.links.self == "/courses/#{Videdal.course_id()}/relationships/instructor"
  end

  test "create validates and maps writable adapter attributes and relationships into model attrs" do
    conn =
      Controller.create(
        conn(),
        create_params(%{"name" => "Science", "slug" => "science"}, %{
          "instructor" => %{"data" => %{"type" => "teachers", "id" => Videdal.teacher_id()}}
        })
      )

    assert conn.status == 201
    assert conn.resp_body.data.type == "courses"
    assert conn.resp_body.data.attributes == %{name: "Science", slug: "science"}

    assert Process.get({Hawk.JsonApiControllerAdapterContractTest.Courses.Writer, :create_attrs}) ==
             %{
               title: "Science",
               public_slug: "science",
               teacher_id: Videdal.teacher_id()
             }
  end

  test "update rejects adapter fields that are not updatable" do
    conn =
      Controller.update(
        conn(),
        Map.put(create_params(%{"slug" => "science"}), "id", Videdal.course_id())
      )

    assert conn.status == 400
    assert [%{detail: "unknown attribute \"slug\""}] = conn.resp_body.errors
  end

  defp create_params(attributes, relationships \\ %{}) do
    %{
      "data" => %{
        "type" => "courses",
        "attributes" => attributes,
        "relationships" => relationships
      }
    }
  end

  defp conn do
    %{assigns: %{authority: Hawk.Authority.system()}, status: nil, resp_body: nil}
  end
end

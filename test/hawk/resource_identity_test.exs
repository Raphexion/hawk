defmodule Hawk.ResourceIdentityTest.Controller do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.CourseRosters,
    public: true
end

defmodule Hawk.ResourceIdentityTest.ShowLive do
  @moduledoc false

  use Hawk.LiveView,
    resource: Videdal.CourseRosters
end

defmodule Hawk.ResourceIdentityTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]
  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.Authority
  alias Hawk.JsonApi.{Document, Schema}
  alias Hawk.ResourceIdentityTest.{Controller, ShowLive}
  alias Videdal.CourseRoster

  @course_id Videdal.course_id()
  @short_id @course_id |> String.split("-") |> List.first()

  defp roster do
    %CourseRoster{course_id: @course_id, title: "Math", enrollment_count: 2}
  end

  test "the facade exposes the declared identity" do
    assert Videdal.CourseRosters.__hawk_resource__(:identity) == :course_id
    assert Schema.identity_for_facade(Videdal.CourseRosters) == :course_id
    assert Schema.identity(Videdal.CourseRoster) == :course_id
    # Default identity for an :id resource is still :id.
    assert Schema.identity(Videdal.Course) == :id
  end

  test "Document renders the identity field as the JSON:API id" do
    document = Document.document(roster())

    assert document.data.id == @course_id
    assert document.data.type == "course-rosters"
    assert document.data.attributes.title == "Math"
  end

  test "show resolves a member by the identity field with a full UUID" do
    Process.put({Videdal.Repo, :all_results}, [roster()])

    conn = Controller.show(conn(Authority.system()), %{"id" => @course_id})

    assert conn.status == 200
    assert resp(conn).data.id == @course_id

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "course_id"
    refute inspect(query) =~ "c0.id =="
  end

  test "show resolves a short id through an indexed UUID range on the identity field" do
    Process.put({Videdal.Repo, :all_results}, [roster()])

    conn = Controller.show(conn(Authority.system()), %{"id" => @short_id})

    assert conn.status == 200
    assert resp(conn).data.id == @course_id

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "c0.course_id >= ^"
    assert inspect(query) =~ "c0.course_id <= ^"
  end

  test "show returns not found when no roster matches the identity" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn = Controller.show(conn(Authority.system()), %{"id" => @course_id})

    assert conn.status == 404
    assert [%{code: "not_found"}] = resp(conn).errors
  end

  test "OpenAPI renders the identity-keyed resource without assuming :id" do
    spec = Hawk.OpenApi.spec([Videdal.CourseRosters])

    assert Map.has_key?(spec.paths, "/course-rosters")
    assert Map.has_key?(spec.components.schemas, :CourseRosterResource)

    resource = Map.fetch!(spec.components.schemas, :CourseRosterResource)
    assert resource[:"x-resource-type"] == "course-rosters"
    assert resource.properties.attributes.properties == %{
             title: %{type: "string", description: "Course title as shown on the roster.", example: "Math"},
             enrollment_count: %{type: "integer", description: "Number of enrolled students.", example: 2}
           }
  end

  test "LiveView assign_show loads a member by the identity field" do
    Process.put({Videdal.Repo, :all_results}, [roster()])

    socket = ShowLive.assign_show(socket(), Authority.system(), @course_id)

    assert socket.assigns.roster == roster()
    assert socket.assigns.hawk_resource == :roster

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "course_id"
    refute inspect(query) =~ "c0.id =="
  end

  test "the resource contract validates an identity-keyed resource" do
    assert :ok = Hawk.ResourceContract.validate!(Videdal.CourseRosters, Videdal.CourseRoster)
  end

  test "declaring an identity field that is not on the model fails at compile time" do
    assert_raise ArgumentError,
                 ~r/Hawk resource identity :missing_key must be a field on Videdal.Course/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadIdentity.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.BadIdentity.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadIdentity.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadIdentity.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.BadIdentity.LiveView do
                     def __hawk_live_view__, do: %{}
                   end

                   defmodule Hawk.ResourceTest.BadIdentity do
                     use Hawk.Resource,
                       model: Videdal.Course,
                       identity: :missing_key
                   end
                   """)
                 end
  end
end

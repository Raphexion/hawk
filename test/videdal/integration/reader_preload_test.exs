defmodule Videdal.Integration.ReaderPreloadTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Student,
    policy: Videdal.Integration.ReaderPreloadTest.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)

  preload(:school)
end

defmodule Videdal.Integration.ReaderPreloadTest.Policy do
  @moduledoc false

  def read_filter(_authority), do: :all
end

defmodule Videdal.Integration.ReaderPreloadTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.{SandboxRepo, School, Student}
  alias Videdal.Integration.ReaderPreloadTest.Reader

  @moduletag :database

  setup do
    Videdal.DatabaseCase.reset_schema!()
    :ok
  end

  test "reader preloads are executed once for the full result set" do
    school = SandboxRepo.insert!(%School{name: "Videdal Skole"})

    SandboxRepo.insert!(%Student{name: "Ada", school_id: school.id})
    SandboxRepo.insert!(%Student{name: "Grace", school_id: school.id})

    {students, query_count} =
      count_queries(fn ->
        Reader.all(authority: Authority.system(), preloads: [:school])
      end)

    assert Enum.map(students, & &1.name) == ["Ada", "Grace"]
    assert Enum.all?(students, &Ecto.assoc_loaded?(&1.school))
    assert Enum.map(students, & &1.school.name) == ["Videdal Skole", "Videdal Skole"]
    assert query_count == 2
  end

  test "preload policy scopes loaded relations without changing the root result set" do
    visible_school = SandboxRepo.insert!(%School{name: "Visible Skole"})
    hidden_school = SandboxRepo.insert!(%School{name: "Hidden Skole"})

    SandboxRepo.insert!(%Student{name: "Ada", school_id: visible_school.id})
    SandboxRepo.insert!(%Student{name: "Grace", school_id: hidden_school.id})

    authority = Authority.new(:school_admin, 1, scopes: %{school_id: visible_school.id})

    {students, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:school])
      end)

    assert Enum.map(students, & &1.name) == ["Ada", "Grace"]
    assert [%Student{school: %School{name: "Visible Skole"}}, %Student{school: nil}] = students
    assert query_count == 2
  end

  test "reader without preloads performs only the base query and leaves relations unloaded" do
    school = SandboxRepo.insert!(%School{name: "No Preload Skole"})
    SandboxRepo.insert!(%Student{name: "Alan", school_id: school.id})

    {students, query_count} =
      count_queries(fn ->
        Reader.all(authority: Authority.system(), filter: %{school_id: school.id})
      end)

    assert [%Student{name: "Alan", school: %Ecto.Association.NotLoaded{}}] = students
    assert query_count == 1
  end
end

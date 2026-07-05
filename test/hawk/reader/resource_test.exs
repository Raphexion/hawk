defmodule Hawk.Reader.ResourceTest.Policy do
  @moduledoc false

  def read_filter(_authority), do: %{school_id: 7}
end

defmodule Hawk.Reader.ResourceTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)

  preload(:school, policy: Videdal.Schools.Policy)

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([student], student.id == ^student_id)
    end
  end

  attach :school, when_filter: [:school_name], when_sort: [:school_name] do
    join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end
end

defmodule Hawk.Reader.ResourceTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Reader.ResourceTest.Reader
  alias Videdal.Student

  test "generates reader metadata functions" do
    assert Reader.filter_keys() ==
             MapSet.new([:id, :school_id, :active, :student_id, :school_name])

    assert Map.has_key?(Reader.filter_handlers(), :student_id)
    assert [%{name: :school, when_filter: when_filter, when_sort: when_sort}] = Reader.join_plan()
    assert when_filter == MapSet.new([:school_name])
    assert when_sort == MapSet.new([:school_name])
    assert Reader.preload_keys() == MapSet.new([:school])

    assert Reader.preload_policies() == %{school: Videdal.Schools.Policy}

    assert Reader.read_filter(Authority.system()) == %{school_id: 7}
  end

  test "generates all/1 through the shared reader runtime" do
    Process.put({Videdal.Repo, :all_results}, [%Student{id: 12, school_id: 7}])

    assert [%Student{id: 12}] =
             Reader.all(authority: Authority.system(), filter: %{student_id: 12})

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "s0.id == ^12"
    assert inspected =~ "s0.school_id == ^7"
    refute inspected =~ "join:"
  end

  test "applies explicit join steps only when triggered by filters" do
    Process.put({Videdal.Repo, :all_results}, [%Student{id: 12, school_id: 7}])

    Reader.all(authority: Authority.system(), filter: %{school_name: "Videdal Skole"})

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(s0, :school)"
    assert inspected =~ ~s(s1.name == ^"Videdal Skole")
  end

  test "preloads declared associations after fetching rows" do
    results = [%Student{id: 12, school_id: 7}]
    Process.put({Videdal.Repo, :all_results}, results)

    assert Reader.all(authority: Authority.system(), preloads: [:school]) == results

    assert_received {:videdal_repo, :all, _query}
    assert_received {:videdal_repo, :preload, ^results, [school: %Ecto.Query{}]}
    refute_received {:videdal_repo, :preload, _other_results, _preloads}
  end

  test "rejects undeclared preloads" do
    assert_raise ArgumentError, ~r/unknown reader preload :courses/, fn ->
      Reader.all(authority: Authority.system(), preloads: [:courses])
    end
  end

  test "generates one/1 and one!/1" do
    student = %Student{id: 12, school_id: 7}
    Process.put({Videdal.Repo, :all_results}, [student])

    assert Reader.one(authority: Authority.system(), filter: %{student_id: 12}) == {:ok, student}
    assert Reader.one!(authority: Authority.system(), filter: %{student_id: 12}) == student
  end
end

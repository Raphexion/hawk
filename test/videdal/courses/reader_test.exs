defmodule Videdal.Courses.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Courses
  alias Videdal.Courses.Reader

  test "declares the resource filter keys and preloads" do
    assert Reader.filter_keys() ==
             MapSet.new([:id, :title, :school_id, :teacher_id, :school_name, :teacher_name])

    assert Reader.preload_keys() == MapSet.new([:school, :teacher, :grades, :enrollments])
    assert Reader.preload_readers() == %{}
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Reader.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end

  test "all/1 applies explicit joins for school and teacher filters" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Courses.all(
             authority: Authority.system(),
             filter: %{school_name: "Videdal", teacher_name: "Grace"}
           ) == []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(c0, :school)"
    assert inspected =~ "join: t2 in assoc(c0, :teacher)"
    assert inspected =~ ~s(s1.name == ^"Videdal")
    assert inspected =~ ~s(t2.name == ^"Grace")
  end

  test "all/1 preloads declared school and teacher associations once" do
    results = [%Videdal.Course{id: 1, school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, results)

    assert Courses.all(authority: Authority.system(), preloads: [:school, :teacher]) == results

    assert_received {:videdal_repo, :all, _query}

    assert_received {:videdal_repo, :preload, ^results,
                     [school: %Ecto.Query{}, teacher: %Ecto.Query{}]}

    refute_received {:videdal_repo, :preload, _other_results, _preloads}
  end
end

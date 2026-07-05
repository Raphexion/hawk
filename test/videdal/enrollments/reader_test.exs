defmodule Videdal.Enrollments.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Enrollments.Reader

  test "declares the resource filter keys and preloads" do
    assert Reader.filter_keys() ==
             MapSet.new([
               :id,
               :school_id,
               :student_id,
               :course_id,
               :enrolled_on_or_after,
               :student_name,
               :course_title
             ])

    assert Reader.preload_keys() == MapSet.new([:school, :student, :course])
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert Reader.read_filter(authority) == %{school_id: 7, student_id: 8}
  end

  test "all/1 applies the enrolled_on_or_after custom filter handler" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Videdal.Enrollments.all(
             authority: Authority.system(),
             filter: %{enrolled_on_or_after: ~D[2026-01-01]}
           ) == []

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "e0.enrolled_on >= ^~D[2026-01-01]"
  end

  test "all/1 applies explicit joins for related student and course filters" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Videdal.Enrollments.all(
             authority: Authority.system(),
             filter: %{student_name: "Ada", course_title: "Math"}
           ) == []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(e0, :student)"
    assert inspected =~ "join: c2 in assoc(e0, :course)"
    assert inspected =~ ~s(s1.name == ^"Ada")
    assert inspected =~ ~s(c2.title == ^"Math")
  end

  test "all/1 preloads declared nested associations once" do
    results = [%Videdal.Enrollment{id: 1, school_id: 7, student_id: 8, course_id: 3}]
    preloads = [:school, student: [:school], course: [:teacher]]
    Process.put({Videdal.Repo, :all_results}, results)

    assert Videdal.Enrollments.all(authority: Authority.system(), preloads: preloads) == results

    assert_received {:videdal_repo, :all, _query}

    assert_received {:videdal_repo, :preload, ^results,
                     [
                       school: %Ecto.Query{},
                       student: {%Ecto.Query{}, [:school]},
                       course: {%Ecto.Query{}, [:teacher]}
                     ]}

    refute_received {:videdal_repo, :preload, _other_results, _preloads}
  end
end

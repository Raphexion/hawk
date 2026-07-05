defmodule Videdal.Students.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Student
  alias Videdal.Students
  alias Videdal.Students.Reader

  test "declares the resource filter keys" do
    assert MapSet.subset?(
             MapSet.new([:id, :school_id, :student_id, :active, :school_name]),
             Reader.filter_keys()
           )
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert Reader.read_filter(authority) == %{school_id: 7}
  end

  test "all/1 combines caller filters with policy filters and calls the repo" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})
    put_repo_results([%Student{id: 1, name: "Ada", school_id: 7}])

    assert [%Student{name: "Ada"}] = Students.all(authority: authority, filter: %{active: true})

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "where:"
    assert inspected =~ "s0.active == ^true"
    assert inspected =~ "s0.school_id == ^7"
    assert inspected =~ "order_by: [asc: s0.id]"
  end

  test "all/1 applies the student_id custom filter handler" do
    put_repo_results([])

    assert Students.all(authority: Authority.system(), filter: %{student_id: 12}) == []

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "s0.id == ^12"
  end

  test "all/1 applies explicit school joins only when a related filter is active" do
    put_repo_results([])

    assert Students.all(authority: Authority.system(), filter: %{school_name: "Videdal Skole"}) ==
             []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(s0, :school)"
    assert inspected =~ ~s(s1.name == ^"Videdal Skole")
  end

  test "all/1 applies limit from page size" do
    put_repo_results([])

    assert Students.all(authority: Authority.system(), page: %{size: 5}) == []

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "limit: ^5"
  end

  test "all/1 preloads declared associations" do
    results = [%Student{id: 1, name: "Ada", school_id: 7}]
    put_repo_results(results)

    assert Students.all(authority: Authority.system(), preloads: [:school]) == results

    assert_received {:videdal_repo, :all, _query}
    assert_received {:videdal_repo, :preload, ^results, [:school]}
    refute_received {:videdal_repo, :preload, _other_results, [:school]}
  end

  test "all/1 rejects undeclared preloads" do
    assert_raise ArgumentError, ~r/unknown reader preload :courses/, fn ->
      Students.all(authority: Authority.system(), preloads: [:courses])
    end
  end

  test "all/1 rejects unknown options" do
    assert_raise ArgumentError, ~r/unknown reader option :unexpected/, fn ->
      Students.all(authority: Authority.system(), unexpected: true)
    end
  end

  test "all/1 rejects invalid sort directions" do
    assert_raise ArgumentError, ~r/invalid sort direction :sideways/, fn ->
      Students.all(authority: Authority.system(), page: %{dir: :sideways})
    end
  end

  test "all/1 rejects unknown filter keys before compiling" do
    assert_raise ArgumentError, ~r/unknown filter key :campus_id/, fn ->
      Students.all(authority: Authority.system(), filter: %{campus_id: 1})
    end
  end

  test "one/1 returns ok for exactly one result" do
    student = %Student{id: 1, name: "Ada"}
    put_repo_results([student])

    assert Students.one(authority: Authority.system(), filter: %{id: 1}) == {:ok, student}
  end

  test "one/1 returns not_found for zero results" do
    put_repo_results([])

    assert Students.one(authority: Authority.system(), filter: %{id: 1}) == :not_found
  end

  test "one/1 raises for multiple results" do
    put_repo_results([%Student{id: 1}, %Student{id: 2}])

    assert_raise RuntimeError, ~r/expected one result, got 2/, fn ->
      Students.one(authority: Authority.system(), filter: %{active: true})
    end
  end

  test "one!/1 returns the model or raises when missing" do
    student = %Student{id: 1, name: "Ada"}
    put_repo_results([student])

    assert Students.one!(authority: Authority.system(), filter: %{id: 1}) == student

    put_repo_results([])

    assert_raise RuntimeError, ~r/expected one result, got none/, fn ->
      Students.one!(authority: Authority.system(), filter: %{id: 2})
    end
  end

  defp put_repo_results(results) do
    Process.put({Videdal.Repo, :all_results}, results)
  end
end

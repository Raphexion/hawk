defmodule Videdal.Students.ReaderTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.Students
  alias Videdal.Students.Reader

  test "declares the resource filter keys" do
    assert MapSet.subset?(
             MapSet.new([:id, :school_id, :student_id, :active, :school_name, :parent_id]),
             Reader.filter_keys()
           )
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert Reader.read_filter(authority) == %{school_id: 7}
  end

  test "all/1 combines caller filters with policy filters" do
    school = insert(:school)
    student = insert(:student, school_id: school.id, active: true)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    [result] = Students.all(authority: authority, filter: %{active: true})

    assert result.id == student.id
  end

  test "all/1 applies the student_id custom filter handler" do
    insert(:student)
    student = insert(:student)

    assert [result] = Students.all(authority: Authority.system(), filter: %{student_id: student.id})
    assert result.id == student.id
  end

  test "all/1 applies explicit school joins only when a related filter is active" do
    school = insert(:school, name: "Test School")
    student = insert(:student, school_id: school.id)

    assert [result] = Students.all(authority: Authority.system(), filter: %{school_name: "Test School"})
    assert result.id == student.id
  end

  test "all/1 applies limit from page size" do
    insert_list(3, :student)

    results = Students.all(authority: Authority.system(), page: %{size: 2})

    assert length(results) == 2
  end

  test "all/1 preloads declared associations" do
    student = insert(:student)

    [result] = Students.all(authority: Authority.system(), preloads: [:school])

    assert Ecto.assoc_loaded?(result.school)
    assert result.school.id == student.school_id
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
    assert_raise ArgumentError, ~r/invalid sort clause/, fn ->
      Students.all(authority: Authority.system(), sort: [{:sideways, :id}])
    end
  end

  test "all/1 rejects unknown filter keys before compiling" do
    assert_raise ArgumentError, ~r/unknown filter key :campus_id/, fn ->
      Students.all(authority: Authority.system(), filter: %{campus_id: 1})
    end
  end

  test "one/1 returns ok for exactly one result" do
    student = insert(:student)

    assert {:ok, found} = Students.one(authority: Authority.system(), filter: %{id: student.id})
    assert found.id == student.id
  end

  test "one/1 returns not_found for zero results" do
    assert :not_found = Students.one(authority: Authority.system(), filter: %{id: Ecto.UUID.generate()})
  end

  test "one/1 raises for multiple results" do
    school = insert(:school)
    insert(:student, school_id: school.id)
    insert(:student, school_id: school.id)

    assert_raise RuntimeError, ~r/expected one result, got 2/, fn ->
      Students.one(authority: Authority.system(), filter: %{school_id: school.id})
    end
  end
end

defmodule Videdal.Grades.PreloadQueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Hawk.Authority
  alias Videdal.Grades.Reader

  test "reader-owned preload query applies unrestricted policy" do
    query = Reader.preload_query(base_query(), Authority.system())

    refute inspect(query) =~ "where:"
  end

  test "reader-owned preload query applies fail-closed policy" do
    query = Reader.preload_query(base_query(), Authority.new(:unknown, 1))

    assert inspect(query) =~ "where: false"
  end

  test "reader-owned preload query applies school-scoped policy" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})
    query = Reader.preload_query(base_query(), authority)

    assert inspect(query) =~ "g0.school_id == ^7"
  end

  test "reader-owned preload query uses explicit joins for teacher policy" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})
    query = Reader.preload_query(base_query(), authority)
    inspected = inspect(query)

    assert inspected =~ "join: c1 in assoc(g0, :course)"
    assert inspected =~ "g0.school_id == ^7"
    assert inspected =~ "c1.teacher_id == ^12"
  end

  test "reader-owned preload query uses explicit joins for parent policy" do
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})
    query = Reader.preload_query(base_query(), authority)
    inspected = inspect(query)

    assert inspected =~ "join: s1 in assoc(g0, :student)"
    assert inspected =~ "join: p2 in assoc(s1, :parent_students)"
    assert inspected =~ "g0.school_id == ^7"
    assert inspected =~ "p2.parent_id == ^4"
  end

  defp base_query do
    from(Videdal.Grade, as: :root)
  end
end

defmodule Videdal.Enrollments.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Enrollments.Reader

  test "declares the resource filter keys" do
    assert Reader.filter_keys() ==
             MapSet.new([:id, :school_id, :student_id, :course_id, :enrolled_on_or_after])
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
end

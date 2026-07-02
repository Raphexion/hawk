defmodule Videdal.Teachers.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Teachers.Reader

  test "declares the resource filter keys" do
    assert Reader.filter_keys() == MapSet.new([:id, :school_id, :teacher_id])
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Reader.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end

  test "all/1 applies the teacher_id custom filter handler" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Videdal.Teachers.all(authority: Authority.system(), filter: %{teacher_id: 12}) == []

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "t0.id == ^12"
  end
end

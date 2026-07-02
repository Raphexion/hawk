defmodule Hawk.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Reader
  alias Videdal.Repo
  alias Videdal.Student
  alias Videdal.Students

  test "build_query combines caller, policy, and forced filters" do
    config = %{
      repo: Repo,
      schema: Student,
      filter_keys: MapSet.put(Students.Reader.filter_keys(), :name),
      read_filter: fn _authority -> %{school_id: 7} end,
      forced_filter: %{active: true}
    }

    query = Reader.build_query(config, authority: Authority.system(), filter: %{name: "Ada"})

    inspected = inspect(query)
    assert inspected =~ ~s(s0.name == ^"Ada")
    assert inspected =~ "s0.school_id == ^7"
    assert inspected =~ "s0.active == ^true"
  end

  test "requires authority" do
    config = %{
      repo: Repo,
      schema: Student,
      filter_keys: Students.Reader.filter_keys(),
      read_filter: fn _authority -> :all end
    }

    assert_raise KeyError, fn ->
      Reader.build_query(config, filter: %{name: "Ada"})
    end
  end
end

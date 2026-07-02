defmodule Hawk.Reader.ResourceTest.Policy do
  @moduledoc false

  def read_filter(_authority), do: %{school_id: 7}
end

defmodule Hawk.Reader.ResourceTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: &Hawk.Reader.ResourceTest.Policy.read_filter/1

  filter(:id)
  filter(:school_id)
  filter(:active)

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([student], student.id == ^student_id)
    end
  end
end

defmodule Hawk.Reader.ResourceTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Reader.ResourceTest.Reader
  alias Videdal.Student

  test "generates reader metadata functions" do
    assert Reader.filter_keys() == MapSet.new([:id, :school_id, :active, :student_id])
    assert Map.has_key?(Reader.filter_handlers(), :student_id)
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
  end

  test "generates one/1 and one!/1" do
    student = %Student{id: 12, school_id: 7}
    Process.put({Videdal.Repo, :all_results}, [student])

    assert Reader.one(authority: Authority.system(), filter: %{student_id: 12}) == {:ok, student}
    assert Reader.one!(authority: Authority.system(), filter: %{student_id: 12}) == student
  end
end

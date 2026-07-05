defmodule Hawk.ReaderFilterJourneyTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.School,
    policy: Videdal.Schools.Policy

  filter(:id)
  filter(:name)

  filter :noop do
    fn
      {:eq, true} -> :all
      {:eq, false} -> :none
    end
  end
end

defmodule Hawk.ReaderFilterJourneyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.ReaderFilterJourneyTest.Reader

  test "reader filters can travel through OR, none, and non-equality operators" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Reader.all(
             authority: Authority.system(),
             filter: {:or, %{name: {:neq, "Closed"}}, :none}
           ) == []

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ ~s(s0.name != ^"Closed")
  end

  test "reader custom filters can intentionally expand to all or none" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Reader.all(authority: Authority.system(), filter: %{noop: true}) == []
    assert_received {:videdal_repo, :all, all_query}
    refute inspect(all_query) =~ "where:"

    assert Reader.all(authority: Authority.system(), filter: %{noop: false}) == []
    assert_received {:videdal_repo, :all, none_query}
    assert inspect(none_query) =~ "where: false"
  end
end

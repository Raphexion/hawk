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
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Hawk.ReaderFilterJourneyTest.Reader

  test "reader filters can travel through OR, none, and non-equality operators" do
    insert(:school, name: "Open")
    insert(:school, name: "Closed")

    results = Reader.all(authority: Authority.system(), filter: {:or, %{name: {:neq, "Closed"}}, :none})

    assert length(results) == 1
    assert hd(results).name == "Open"
  end

  test "reader custom filters can intentionally expand to all or none" do
    insert(:school, name: "A")
    insert(:school, name: "B")

    assert length(Reader.all(authority: Authority.system(), filter: %{noop: true})) == 2

    assert Reader.all(authority: Authority.system(), filter: %{noop: false}) == []
  end
end

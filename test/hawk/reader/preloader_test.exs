defmodule Hawk.Reader.PreloaderTest.ParentlessPolicy do
  @moduledoc false
end

defmodule Hawk.Reader.PreloaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Reader.Preloader
  alias Videdal.Student

  test "empty preloads are a no-op" do
    results = [%Student{id: 1}]

    assert Preloader.preload(results, Videdal.Repo, [], [:school]) == results
    refute_received {:videdal_repo, :preload, _results, _preloads}
  end

  test "declared preloads are delegated to the repo once for the result list" do
    results = [%Student{id: 1}, %Student{id: 2}]

    assert Preloader.preload(results, Videdal.Repo, [:school], [:school]) == results
    assert_received {:videdal_repo, :preload, ^results, [:school]}
    refute_received {:videdal_repo, :preload, _other_results, [:school]}
  end

  test "unknown preloads fail loudly" do
    assert_raise ArgumentError, ~r/unknown reader preload :courses/, fn ->
      Preloader.preload([], Videdal.Repo, [:courses], [:school])
    end
  end

  test "invalid preload shapes fail loudly" do
    assert_raise ArgumentError, ~r/invalid reader preload/, fn ->
      Preloader.preload([], Videdal.Repo, ["school"], [:school])
    end
  end

  test "non-list preloads fail loudly in policy-aware path" do
    assert_raise ArgumentError, ~r/preloads must be a list/, fn ->
      Preloader.preload([], Videdal.Repo, :school, [:school], Hawk.Authority.system(), %{})
    end
  end

  test "multiple unknown preloads fail loudly" do
    assert_raise ArgumentError, ~r/unknown reader preloads :courses, :teachers/, fn ->
      Preloader.preload([], Videdal.Repo, [:courses, :teachers], [:school])
    end
  end

  test "empty results skip policy query construction" do
    assert Preloader.preload(
             [],
             Videdal.Repo,
             [:school],
             [:school],
             Hawk.Authority.system(),
             %{school: Hawk.Reader.PreloaderTest.ParentlessPolicy}
           ) == []
  end

  test "nested policy preloads are delegated as query tuples" do
    results = [%Student{id: 1}]

    assert Preloader.preload(
             results,
             Videdal.Repo,
             [school: []],
             [:school],
             Hawk.Authority.system(),
             %{school: Videdal.Schools.Policy}
           ) == results

    assert_received {:videdal_repo, :preload, ^results, [school: {%Ecto.Query{}, []}]}
  end

  test "policy-aware path requires every preload to have a reader or model association policy" do
    assert_raise ArgumentError, ~r/must declare a policy module/, fn ->
      Preloader.preload(
        [%Videdal.School{id: 1}],
        Videdal.Repo,
        [:students],
        [:students],
        Hawk.Authority.system(),
        %{}
      )
    end
  end

  test "policy modules must define read_filter/1" do
    assert_raise ArgumentError, ~r/must define read_filter\/1/, fn ->
      Preloader.preload(
        [%Student{id: 1}],
        Videdal.Repo,
        [:school],
        [:school],
        Hawk.Authority.system(),
        %{school: Hawk.Reader.PreloaderTest.ParentlessPolicy}
      )
    end
  end
end

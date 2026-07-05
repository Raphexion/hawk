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
end

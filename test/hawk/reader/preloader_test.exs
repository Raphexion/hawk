defmodule Hawk.Reader.PreloaderTest.ParentlessReader do
  @moduledoc false
end

defmodule Hawk.Reader.PreloaderTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Reader.Preloader
  alias Videdal.{Repo, Student}

  test "empty preloads are a no-op" do
    results = [%Student{id: Ecto.UUID.generate()}]

    assert Preloader.preload(results, Repo, [], [:school]) == results
  end

  test "declared preloads are delegated to the repo once for the result list" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)

    [result] = Preloader.preload([student], Repo, [:school], [:school])

    assert Ecto.assoc_loaded?(result.school)
    assert result.school.id == school.id
  end

  test "unknown preloads fails loudly" do
    assert_raise ArgumentError, ~r/unknown reader preload :courses/, fn ->
      Preloader.preload([], Repo, [:courses], [:school])
    end
  end

  test "reader-aware path requires every preload to have a reader on the reader or model association" do
    assert_raise ArgumentError, ~r/must declare a reader module/, fn ->
      Preloader.preload(
        [%Videdal.School{id: Ecto.UUID.generate()}],
        Repo,
        [:students],
        [:students],
        Hawk.Authority.system(),
        %{}
      )
    end
  end

  test "reader modules must define preload_query/2" do
    assert_raise ArgumentError, ~r/must define preload_query\/2/, fn ->
      Preloader.preload(
        [%Student{id: Ecto.UUID.generate()}],
        Repo,
        [:school],
        [:school],
        Hawk.Authority.system(),
        %{school: Hawk.Reader.PreloaderTest.ParentlessReader}
      )
    end
  end
end

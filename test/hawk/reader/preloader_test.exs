defmodule Hawk.Reader.PreloaderTest.ParentlessReader do
  @moduledoc false
end

defmodule Hawk.Reader.PreloaderTest.FakeRepo do
  @moduledoc false

  def all(_query) do
    raise "fake repo should not be called"
  end

  def preload(_results, _preloads) do
    raise "fake repo should not be called"
  end
end

defmodule Hawk.Reader.PreloaderTest.BogusNestedReader do
  @moduledoc false

  def preload_keys, do: MapSet.new([:bogus])
  def preload_readers, do: %{bogus: Videdal.Students.Reader}
  def preload_query(query, _authority), do: query
end

defmodule Hawk.Reader.PreloaderTest.BrokenNestedReader do
  @moduledoc false

  def preload_keys, do: MapSet.new([:student])
  def preload_readers, do: %{student: Hawk.Reader.PreloaderTest.ParentlessReader}
  def preload_query(query, _authority), do: query
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

  test "reader-aware validation requires every top-level preload to have a reader" do
    assert_raise ArgumentError, ~r/must declare a reader module/, fn ->
      Preloader.validate_preloads!([:students], [:students], Videdal.School, %{})
    end
  end

  test "reader all fails before querying the repo for a broken top-level preload reader" do
    config = %{
      repo: Hawk.Reader.PreloaderTest.FakeRepo,
      schema: Videdal.School,
      filter_keys: [],
      read_filter: fn _authority -> :all end,
      preload_keys: [:students]
    }

    assert_raise ArgumentError, ~r/must declare a reader module/, fn ->
      Hawk.Reader.all(config, authority: Hawk.Authority.system(), preloads: [:students])
    end
  end

  test "reader-aware validation requires top-level reader modules to define preload_query/2" do
    assert_raise ArgumentError, ~r/must define preload_query\/2/, fn ->
      Preloader.validate_preloads!(
        [:school],
        [:school],
        Student,
        %{school: Hawk.Reader.PreloaderTest.ParentlessReader}
      )
    end
  end

  test "reader-aware validation requires top-level preloads to be schema associations" do
    assert_raise ArgumentError, ~r/must reference an association/, fn ->
      Preloader.validate_preloads!(
        [:students],
        [:students],
        Videdal.School,
        %{students: Videdal.Students.Reader}
      )
    end
  end

  test "reader-aware validation accepts top-level readers declared on the model association" do
    assert :ok = Preloader.validate_preloads!([:school], [:school], Student, %{})
  end

  test "reader-aware validation accepts top-level readers declared on the reader" do
    assert :ok =
             Preloader.validate_preloads!(
               [:school],
               [:school],
               Student,
               %{school: Videdal.Schools.Reader}
             )
  end

  test "reader-aware validation requires nested preloads to be schema associations" do
    assert_raise ArgumentError, ~r/must reference an association on Videdal.Grade/, fn ->
      Preloader.validate_preloads!(
        [grades: [:bogus]],
        [:grades],
        Student,
        %{grades: Hawk.Reader.PreloaderTest.BogusNestedReader}
      )
    end
  end

  test "reader-aware validation requires nested readers to define preload_query/2" do
    assert_raise ArgumentError, ~r/reader preload :student reader .* must define preload_query\/2/, fn ->
      Preloader.validate_preloads!(
        [grades: [:student]],
        [:grades],
        Student,
        %{grades: Hawk.Reader.PreloaderTest.BrokenNestedReader}
      )
    end
  end

  test "reader-aware validation accepts nested preloads declared by the associated reader" do
    assert :ok = Preloader.validate_preloads!([grades: [:student]], [:grades], Student, %{})
  end
end

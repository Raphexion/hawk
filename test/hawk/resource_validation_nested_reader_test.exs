defmodule Hawk.ResourceValidationNestedReaderTest.Course do
  use Hawk.Model

  model "resource_validation_nested_reader_test_courses" do
    has_many(:lessons, Hawk.ResourceValidationNestedReaderTest.Lesson)
  end
end

defmodule Hawk.ResourceValidationNestedReaderTest.Lesson do
  use Hawk.Model

  model "resource_validation_nested_reader_test_lessons" do
    has_many(:cards, Hawk.ResourceValidationNestedReaderTest.Card)
  end
end

defmodule Hawk.ResourceValidationNestedReaderTest.Card do
  use Hawk.Model

  model "resource_validation_nested_reader_test_cards" do
    field(:front, :string)
  end
end

defmodule Hawk.ResourceValidationNestedReaderTest.Courses.Reader do
  def one(_opts), do: :one
  def all(_opts), do: :all
  def filter_keys, do: MapSet.new()
  def sort_keys, do: MapSet.new()
  def preload_keys, do: MapSet.new([:lessons])
end

defmodule Hawk.ResourceValidationNestedReaderTest.Courses.LiveView do
  def __hawk_live_view__ do
    %{
      index: %{table: [%{name: :card_count, source: [:lessons, :cards]}]},
      show: %{}
    }
  end
end

defmodule Hawk.ResourceValidationNestedReaderTest do
  use ExUnit.Case, async: false

  alias Hawk.ResourceValidationNestedReaderTest.{Course, Courses}

  defp modules do
    %{
      model: Course,
      reader: Courses.Reader,
      policy: false,
      writer: false,
      json_api: false,
      live_view: Courses.LiveView,
      actions: false
    }
  end

  test "compile validation silently defers nested readers" do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert :ok = Hawk.Resource.Validation.validate!(modules(), :compile)
      end)

    assert output == ""
  end

  test "strict validation still rejects unavailable nested readers" do
    assert_raise ArgumentError, ~r/nested reader module .* is not available/, fn ->
      Hawk.Resource.Validation.validate!(modules(), :strict)
    end
  end

  test "strict validation reads reloaded nested reader metadata" do
    nested_reader = Hawk.ResourceValidationNestedReaderTest.Lessons.Reader

    on_exit(fn ->
      :code.purge(nested_reader)
      :code.delete(nested_reader)
    end)

    compile_nested_reader([:cards])
    assert :ok = Hawk.Resource.Validation.validate!(modules(), :strict)

    compile_nested_reader([])

    assert :ok = Hawk.Resource.Validation.validate!(modules(), :compile)

    assert_raise ArgumentError, ~r/reaches nested association :cards/, fn ->
      Hawk.Resource.Validation.validate!(modules(), :strict)
    end

    compile_nested_reader([:cards])
    assert :ok = Hawk.Resource.Validation.validate!(modules(), :strict)
  end

  defp compile_nested_reader(preloads) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      Code.compile_string("""
      defmodule Hawk.ResourceValidationNestedReaderTest.Lessons.Reader do
        def preload_keys, do: MapSet.new(#{inspect(preloads)})
      end
      """)
    end)
  end
end

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
  use ExUnit.Case, async: true

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

  test "compile validation defers unavailable nested readers" do
    warning =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert :ok = Hawk.Resource.Validation.validate!(modules(), :compile)
      end)

    assert warning =~ "nested reader module"
    assert warning =~ "Run `mix hawk.validate` to enforce"
  end

  test "strict validation still rejects unavailable nested readers" do
    assert_raise ArgumentError, ~r/nested reader module .* is not available/, fn ->
      Hawk.Resource.Validation.validate!(modules(), :strict)
    end
  end
end

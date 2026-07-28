defmodule Videdal.CourseGradeSummaries.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.CourseGradeSummaries.Reader

  test "declares summary filters" do
    assert Reader.filter_keys() == MapSet.new([:school_id, :course_id])
  end

  test "every authority can read summaries" do
    assert Reader.read_filter(Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})) ==
             :all

    assert Reader.read_filter(Authority.new(:unknown, 1)) == :all
  end
end

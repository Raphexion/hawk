defmodule Videdal.CourseGradeSummaries.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.CourseGradeSummaries
  alias Videdal.CourseGradeSummaries.Reader

  test "declares summary filters" do
    assert Reader.filter_keys() == MapSet.new([:school_id, :course_id])
  end

  test "every authority can read summaries" do
    assert Reader.read_filter(Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})) ==
             :all

    assert Reader.read_filter(Authority.new(:unknown, 1)) == :all
  end

  test "summaries are readable through the facade" do
    results = [
      %Videdal.CourseGradeSummary{school_id: 7, course_id: 3, grade_count: 2, average_score: 11.0}
    ]

    Process.put({Videdal.Repo, :all_results}, results)

    assert CourseGradeSummaries.all(
             authority: Authority.new(:unknown, 1),
             filter: %{course_id: 3}
           ) ==
             results

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "c0.course_id == ^3"
  end
end

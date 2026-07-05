defmodule Videdal.CourseGradeSummaries.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.{CourseGradeSummaries, CourseGradeSummary}

  test "summaries cannot be created by anyone" do
    assert {:not_authorized, context} =
             CourseGradeSummaries.create(%{school_id: 7, course_id: 3}, Authority.system())

    assert context.policy_validated?
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "summaries cannot be updated by anyone" do
    summary = %CourseGradeSummary{school_id: 7, course_id: 3, grade_count: 2, average_score: 11.0}

    assert {:not_authorized, _context} =
             CourseGradeSummaries.update(
               summary,
               %{average_score: 12.0},
               Authority.new(:principal, 1)
             )

    refute_received {:videdal_repo, :update, _changeset}
  end

  test "summaries cannot be deleted by anyone" do
    summary = %CourseGradeSummary{school_id: 7, course_id: 3, grade_count: 2, average_score: 11.0}

    assert {:not_authorized, _context} = CourseGradeSummaries.delete(summary, Authority.system())
    refute_received {:videdal_repo, :delete, _summary}
  end
end

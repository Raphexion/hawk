defmodule Videdal.Enrollments.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Enrollments` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Enrollment,
    policy: &Videdal.Enrollments.Policy.read_filter/1

  filter(:id)
  filter(:school_id)
  filter(:student_id)
  filter(:course_id)

  filter :enrolled_on_or_after do
    fn
      {:eq, date} -> dynamic([enrollment], enrollment.enrolled_on >= ^date)
      {:gte, date} -> dynamic([enrollment], enrollment.enrolled_on >= ^date)
    end
  end
end

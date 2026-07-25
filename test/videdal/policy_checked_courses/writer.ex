defmodule Videdal.PolicyCheckedCourses.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.SandboxRepo,
    policy: Videdal.PolicyCheckedCourses.Policy

  create do
    cast([:title, :registration_state, :seat_count, :waitlist_count, :school_id, :teacher_id])
  end

  update do
    cast([:title, :registration_state, :seat_count, :waitlist_count, :school_id, :teacher_id])
  end

  def delete(%Videdal.Course{} = course, authority) do
    Hawk.MutationContext.delete(course, authority)
    |> Hawk.MutationContext.validate_policy(&Videdal.PolicyCheckedCourses.Policy.delete?/1)
    |> Hawk.RepositoryBoundary.delete(Videdal.SandboxRepo)
  end
end

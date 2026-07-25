defmodule Videdal.CourseCatalog.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.CourseCatalog.Policy

  create do
    cast([:title, :registration_state, :seat_count, :waitlist_count, :school_id, :teacher_id])
  end

  update do
    cast([:title, :registration_state, :seat_count, :waitlist_count, :school_id, :teacher_id])
  end

  def delete(%Videdal.Course{} = course, authority) do
    Hawk.MutationContext.delete(course, authority)
    |> Hawk.MutationContext.validate_policy(&Videdal.CourseCatalog.Policy.delete?/1)
    |> Hawk.RepositoryBoundary.delete(Videdal.Repo)
  end
end

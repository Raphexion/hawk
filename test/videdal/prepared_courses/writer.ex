defmodule Videdal.PreparedCourses.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.PreparedCourses.Policy

  create do
    cast([:title])
  end

  update do
    cast([:title])
  end

  def delete(%Videdal.Course{} = course, authority) do
    Hawk.MutationContext.delete(course, authority)
    |> Hawk.MutationContext.validate_policy(&Videdal.PreparedCourses.Policy.delete?/1)
    |> Hawk.RepositoryBoundary.delete(Videdal.Repo)
  end
end

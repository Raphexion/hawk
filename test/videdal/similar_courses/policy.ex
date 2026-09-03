defmodule Videdal.SimilarCourses.Policy do
  use Hawk.Policy

  @moduledoc """
  Authorization policy for the Videdal similar-courses query.
  """

  read do
    role(:public, :all)
    role(:school_admin, scopes: [:school_id])
  end
end

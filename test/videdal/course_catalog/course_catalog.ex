defmodule Videdal.CourseCatalog do
  @moduledoc """
  Read-only JSON:API resource used by route capability tests.
  """

  use Hawk.Resource,
    model: Videdal.Course,
    writer: false
end

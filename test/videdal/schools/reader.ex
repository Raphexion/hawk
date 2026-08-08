defmodule Videdal.Schools.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Schools` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.School

  filter(:id)
  filter(:name)
  filter(:location, type: :coordinates, max_radius_meters: 100_000)
end

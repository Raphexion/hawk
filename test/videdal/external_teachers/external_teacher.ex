defmodule Videdal.ExternalTeacher do
  @moduledoc """
  Teacher schema used by adapter-contract tests.
  """

  use Hawk.Model

  model "external_teachers" do
    field(:name, :string)
  end
end

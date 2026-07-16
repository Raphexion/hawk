defmodule Videdal.InternalNote do
  @moduledoc """
  Schema for a resource intentionally hidden from JSON:API/OpenAPI.
  """

  use Hawk.Model

  model "internal_notes" do
    field(:body, :string)
  end
end

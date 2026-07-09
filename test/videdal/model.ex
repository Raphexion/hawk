defmodule Videdal.Model do
  @moduledoc """
  Videdal test-domain model defaults.

  Hawk.Model defaults to UUID primary and foreign keys. The Videdal fixture
  schema intentionally uses integer IDs to exercise legacy database shapes.
  """

  defmacro __using__(_opts) do
    quote do
      use Hawk.Model

      @primary_key {:id, :id, autogenerate: true}
      @foreign_key_type :id
    end
  end
end

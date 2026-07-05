defmodule Hawk.ResourceContractCase do
  @moduledoc """
  ExUnit helper for checking that a Hawk resource is wired consistently.

      defmodule MyApp.CoursesContractTest do
        use Hawk.ResourceContractCase,
          resource: MyApp.Courses,
          model: MyApp.Course
      end
  """

  defmacro __using__(opts) do
    resource = Keyword.fetch!(opts, :resource)
    model = Keyword.fetch!(opts, :model)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      test "Hawk resource declarations are consistent" do
        assert :ok = Hawk.ResourceContract.validate!(unquote(resource), unquote(model))
      end
    end
  end
end

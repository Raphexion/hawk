defmodule Hawk.ResourceContractCase do
  @moduledoc """
  ExUnit helper for checking that a Hawk resource is wired consistently.

  Generates a single test that runs `Hawk.ResourceContract.validate!/2` — the
  same cross-checks `mix hawk.validate` runs, but scoped to one resource for
  fast per-resource feedback during development.

      defmodule MyApp.CoursesContractTest do
        use Hawk.ResourceContractCase,
          resource: MyApp.Courses,
          model: MyApp.Course
      end

  ## Options

    * `:resource` (required) — the `Hawk.Resource` facade.
    * `:model` (required) — the backing `Hawk.Model` / `Ecto.Schema`.
    * `:async` — ExUnit async mode (default `true`).
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

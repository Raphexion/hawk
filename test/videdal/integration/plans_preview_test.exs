defmodule Videdal.Integration.PlansPreviewTest do
  @moduledoc """
  Integration test proving Hawk.Plans.preview/2 rolls back a real Postgres
  transaction, leaving no persisted changes.
  """

  use Videdal.DatabaseCase, async: false

  alias Hawk.{Authority, Plan, Plans}
  alias Videdal.Repo

  @authority Authority.system()

  test "preview rolls back: no rows persist after a successful preview" do
    assert Repo.all(Videdal.School) == []

    plan =
      Plan.new([
        %{op: :create, resource: "preview-schools", attrs: %{name: "Preview School"}}
      ])

    {:ok, _effects} = Plans.preview(plan, @authority)

    assert Repo.all(Videdal.School) == []
  end

  test "preview returns effects for the proposed ops" do
    school = Repo.insert!(%Videdal.School{name: "Original"})

    plan =
      Plan.new([
        %{op: :update, resource: "preview-schools", id: school.id, attrs: %{name: "Updated"}}
      ])

    {:ok, effects} = Plans.preview(plan, @authority)

    assert effects.step_1.name == "Updated"

    reloaded = Repo.get!(Videdal.School, school.id)
    assert reloaded.name == "Original"
  end

  test "preview returns error for an invalid plan without persisting" do
    plan =
      Plan.new([
        %{op: :create, resource: "preview-schools", attrs: %{}}
      ])

    result = Plans.preview(plan, @authority)

    assert {:error, :step_1, _reason, _prior} = result
    assert Repo.all(Videdal.School) == []
  end

  test "run commits: changes persist after a successful run" do
    plan =
      Plan.new([
        %{op: :create, resource: "preview-schools", attrs: %{name: "Committed School"}}
      ])

    {:ok, _effects} = Plans.run(plan, @authority, Repo)

    [school] = Repo.all(Videdal.School)
    assert school.name == "Committed School"

    Repo.delete!(school)
  end
end

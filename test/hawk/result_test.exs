defmodule Hawk.ResultTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Hawk.Result
  alias Videdal.Student

  test "returns ok for a valid mutation context" do
    model = %Student{id: 1, name: "Ada"}
    context = MutationContext.new(model, %{}, Authority.system(), :update)

    assert Result.from_context(context, model) == {:ok, model}
  end

  test "returns invalid with context for validation errors" do
    context =
      %Student{}
      |> MutationContext.new(%{}, Authority.system(), :create)
      |> MutationContext.add_error(:name, "can't be blank")

    assert Result.from_context(context, context.model) == {:invalid, context}
  end

  test "returns not authorized with context for policy errors" do
    context =
      %Student{}
      |> MutationContext.new(%{}, Authority.system(), :delete)
      |> MutationContext.validate_policy(fn _context -> false end)

    assert Result.from_context(context, context.model) == {:not_authorized, context}
  end

  test "returns framework errors for repository-level messages" do
    assert Result.error("bulk update failed") == {:error, "bulk update failed"}
  end
end

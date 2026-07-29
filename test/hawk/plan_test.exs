defmodule Hawk.PlanTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Plan

  describe "new/2" do
    test "builds a plan from a list of ops" do
      ops = [
        %{op: :create, resource: "courses", attrs: %{title: "Math"}},
        %{op: :delete, resource: "enrollments", id: "enr-1"}
      ]

      plan = Plan.new(ops)

      assert plan.ops == ops
      assert plan.comments == %{}
      assert plan.authoring_authority == nil
    end

    test "accepts comments and authoring authority via opts" do
      authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

      plan =
        Plan.new(
          [%{op: :delete, resource: "courses", id: "crs-1"}],
          comments: %{plan: "Remove the duplicate course", step_1: "This was created by mistake"},
          authoring_authority: authority
        )

      assert plan.comments.plan == "Remove the duplicate course"
      assert plan.comments.step_1 == "This was created by mistake"
      assert plan.authoring_authority == authority
    end

    test "defaults to empty ops list" do
      plan = Plan.new([])

      assert plan.ops == []
      assert plan.comments == %{}
    end
  end

  describe "struct shape" do
    test "the struct has the expected fields" do
      assert %Plan{ops: [], comments: %{}, authoring_authority: nil} == %Plan{}
    end

    test "ops carry optional comment fields that the executor ignores" do
      ops = [
        %{
          op: :update,
          resource: "courses",
          id: "crs-1",
          attrs: %{title: "Science"},
          comment: "Fixing the title from the sister mix-up"
        }
      ]

      plan = Plan.new(ops)

      assert plan.ops == ops
      assert hd(plan.ops).comment == "Fixing the title from the sister mix-up"
    end
  end

  describe "JSON serialization round-trip" do
    test "a plan serializes to JSON and back without loss" do
      authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

      plan =
        Plan.new(
          [
            %{op: :create, resource: "courses", attrs: %{title: "Math"}},
            %{op: :delete, resource: "enrollments", id: "enr-1", comment: "wrong student"}
          ],
          comments: %{plan: "Fix the sister mix-up"},
          authoring_authority: authority
        )

      # Serialize: the host app stores the plan as JSON. The struct fields are
      # plain data (maps, strings, atoms) except the authoring_authority, which
      # the host app serializes separately via Hawk.Authority.Session.dump/1.
      json =
        Jason.encode!(%{
          ops: plan.ops,
          comments: plan.comments,
          authoring_authority: Hawk.Authority.Session.dump(plan.authoring_authority)
        })

      # Deserialize: reconstruct the plan from JSON. JSON keys/values come back as strings,
      # so the ops won't be atom-keyed. The host app is responsible for atomizing
      # the ops before passing them to Hawk.Plans (the executor expects atom-keyed ops).
      decoded = Jason.decode!(json)
      restored_authority = Hawk.Authority.Session.load(decoded["authoring_authority"])
      restored = Plan.new(decoded["ops"], comments: decoded["comments"], authoring_authority: restored_authority)

      # The ops are structurally preserved (JSON-string keys, not atoms).
      assert length(restored.ops) == length(plan.ops)
      assert hd(restored.ops)["op"] == "create"
      assert hd(restored.ops)["attrs"]["title"] == "Math"
      assert restored.comments["plan"] == "Fix the sister mix-up"
      assert restored.authoring_authority.role == plan.authoring_authority.role
      assert restored.authoring_authority.identity == plan.authoring_authority.identity
      assert restored.authoring_authority.scopes == plan.authoring_authority.scopes
    end
  end
end

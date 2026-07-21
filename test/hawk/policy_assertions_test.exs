defmodule Hawk.PolicyAssertionsTest.ExamplePolicy do
  use Hawk.Policy

  read do
    role(:system, :all)
    role(:teacher, scopes: [:school_id, :teacher_id])
  end
end

defmodule Hawk.PolicyAssertionsTest do
  use ExUnit.Case, async: true

  import Hawk.Policy.Assertions

  alias Hawk.Authority
  alias Hawk.PolicyAssertionsTest.ExamplePolicy

  test "assert_read_matrix checks exact policy filters" do
    assert_read_matrix(ExamplePolicy, [
      {Authority.system(), :all},
      {Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12}), %{school_id: 7, teacher_id: 12}},
      {Authority.new(:teacher, 12, scopes: %{school_id: 7}), :none}
    ])
  end

  test "assert_read_allowed and assert_read_denied check broad access shape" do
    assert_read_allowed(ExamplePolicy, Authority.system())
    assert_read_denied(ExamplePolicy, Authority.new(:unknown, 1))
  end
end

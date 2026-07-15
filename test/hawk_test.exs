defmodule HawkTest do
  use ExUnit.Case
  doctest Hawk

  test "describes Hawk as Phoenix JSON:API infrastructure" do
    assert Hawk.__info__(:module) == Hawk
  end
end

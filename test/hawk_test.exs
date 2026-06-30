defmodule HawkTest do
  use ExUnit.Case
  doctest Hawk

  test "greets the world" do
    assert Hawk.hello() == :world
  end
end

defmodule Videdal.Schools.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Schools.Reader

  test "declares the resource filter keys" do
    assert Reader.filter_keys() == MapSet.new([:id, :name, :location])
    assert Reader.coordinate_filters() == %{location: %{max_radius_meters: 100_000}}
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert Reader.read_filter(authority) == %{id: 7}
  end
end

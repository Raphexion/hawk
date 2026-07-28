defmodule Videdal.Teachers.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Teachers.Reader

  test "declares the resource filter keys and preloads" do
    assert Reader.filter_keys() == MapSet.new([:id, :school_id, :teacher_id, :school_name])
    assert Reader.preload_keys() == MapSet.new([:school])
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Reader.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end
end

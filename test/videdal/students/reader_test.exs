defmodule Videdal.Students.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Students.Reader

  test "declares the resource filter keys" do
    assert MapSet.subset?(
             MapSet.new([:id, :school_id, :student_id, :teacher_id, :active]),
             Reader.filter_keys()
           )
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert Reader.read_filter(authority) == %{school_id: 7}
  end
end

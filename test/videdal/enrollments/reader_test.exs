defmodule Videdal.Enrollments.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Enrollments.Reader

  test "declares the resource filter keys" do
    assert Reader.filter_keys() == MapSet.new([:id, :school_id, :student_id, :course_id])
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert Reader.read_filter(authority) == %{school_id: 7, student_id: 8}
  end
end

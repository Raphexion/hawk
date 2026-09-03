defmodule Videdal.Courses.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Courses.Reader

  test "declares the resource filter keys and preloads" do
    assert Reader.filter_keys() ==
             MapSet.new([:id, :title, :school_id, :teacher_id, :similar_to_course_id, :school_name, :teacher_name])

    assert Reader.preload_keys() == MapSet.new([:school, :teacher, :grades, :enrollments])
    assert Reader.preload_readers() == %{}
  end

  test "delegates read policy to the resource policy module" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Reader.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end
end

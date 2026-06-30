defmodule Videdal do
  @moduledoc """
  Example application namespace used by Hawk's contract tests.

  Videdal models a small school domain. The modules under `test/videdal` are
  intentionally written as a compact example that downstream applications can
  study when adopting Hawk.
  """

  @reader_filter_keys MapSet.new([
                        :id,
                        :school_id,
                        :student_id,
                        :teacher_id,
                        :course_id,
                        :active,
                        :enrolled_on_or_after
                      ])

  def reader_filter_keys, do: @reader_filter_keys
end

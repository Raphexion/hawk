defmodule Videdal.ExternalCourses.Reader do
  @moduledoc false

  def one(_opts), do: {:ok, sample()}
  def one!(_opts), do: sample()
  def all(_opts), do: [sample()]

  def preload_keys, do: [:teacher]
  def sort_keys, do: [:public_slug]

  defp sample do
    %Videdal.ExternalCourse{
      id: Videdal.course_id(),
      title: "Math",
      public_slug: "math",
      teacher_id: Videdal.teacher_id()
    }
  end
end

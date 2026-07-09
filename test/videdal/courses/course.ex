defmodule Videdal.Course do
  @moduledoc """
  Course schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "courses" do
    field(:title, :string)

    belongs_to(:school, Videdal.School)
    belongs_to(:teacher, Videdal.Teacher)
    has_many(:grades, Videdal.Grade)
  end

  json_api do
    type("courses")
    doc("A course taught by a teacher at a school.")

    attribute(:title,
      doc: "Human-readable course title.",
      example: "Math"
    )

    relationship(:school,
      doc: "The school offering the course.",
      example: %{type: "schools", id: "7"}
    )

    relationship(:teacher,
      doc: "The teacher responsible for the course.",
      example: %{type: "teachers", id: "12"}
    )

    relationship(:grades,
      doc: "Grades awarded in this course, filtered through grade visibility rules.",
      example: [%{type: "grades", id: "1"}]
    )

    creatable([:title, :school, :teacher])
    updatable([:title, :school, :teacher])
  end
end

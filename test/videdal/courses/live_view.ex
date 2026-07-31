defmodule Videdal.Courses.LiveView do
  @moduledoc """
  LiveView adapter contract for the Videdal courses resource.
  """

  use Hawk.LiveView.Resource

  as(:course)
  plural_as(:courses)

  index do
    filter(:teacher_id)
    search(:title, operator: :ilike)
    sort(:id)
    sort(:title)

    table do
      column(:title, label: "Course")
      column(:teacher_name, label: "Teacher", source: [:teacher, :name])
      column(:school_name, label: "School", source: [:school, :name])
      column(:registration_state, label: "Registration")
      column(:seat_count, label: "Seats")
      column(:waitlist_count, label: "Waitlist")
    end
  end

  show do
    field(:title)
    field(:teacher_name, label: "Teacher", source: [:teacher, :name])
    field(:registration_state, label: "Registration")
    field(:seat_count, label: "Seats")
    field(:waitlist_count, label: "Waitlist")
  end

  create_form do
    field(:title, label: "Course")
    field(:school_id, label: "School")
    field(:teacher_id, label: "Teacher")
  end

  update_form do
    field(:title, label: "Course")
  end
end

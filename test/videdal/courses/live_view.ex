defmodule Videdal.Courses.LiveView do
  @moduledoc """
  LiveView adapter contract for the Videdal courses resource.
  """

  use Hawk.LiveView.Resource

  as(:course)
  plural_as(:courses)

  index :default do
    table do
      column(:title, label: "Course")
      column(:registration_state, label: "Registration")
      column(:seat_count, label: "Seats")
      column(:waitlist_count, label: "Waitlist")
    end
  end

  show :default do
    field(:title)
    field(:registration_state, label: "Registration")
    field(:seat_count, label: "Seats")
    field(:waitlist_count, label: "Waitlist")
  end
end

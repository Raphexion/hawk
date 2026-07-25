defmodule Videdal.PolicyCheckedCourses.Policy do
  use Hawk.Policy

  @moduledoc false

  # Mirrors Videdal.Courses.Policy so this policy/filter integration vehicle
  # has its own convention-resolved policy module (Hawk.Resource resolves
  # policy as Resource.Policy and no longer accepts a :policy opt).

  read do
    role(:system, :all)
    role(:public, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id, :teacher_id])
    role(:student, scopes: [:school_id])
    role(:parent, scopes: [:school_id])
  end

  write(roles: [:principal, :school_admin])
end

defmodule Videdal.Factory do
  @moduledoc """
  ExMachina factories for Videdal test data.

  Usage in tests:

      school = insert(:school)
      course = insert(:course, school_id: school.id, teacher_id: teacher.id)

  All factories insert real rows into the database via `Videdal.Repo`.
  """

  use ExMachina.Ecto, repo: Videdal.Repo

  def school_factory do
    %Videdal.School{
      id: Ecto.UUID.generate(),
      name: sequence(:school_name, &"School #{&1}")
    }
  end

  def teacher_factory do
    school = insert(:school)

    %Videdal.Teacher{
      id: Ecto.UUID.generate(),
      name: sequence(:teacher_name, &"Teacher #{&1}"),
      school_id: school.id
    }
  end

  def student_factory do
    school = insert(:school)

    %Videdal.Student{
      id: Ecto.UUID.generate(),
      name: sequence(:student_name, &"Student #{&1}"),
      active: true,
      school_id: school.id
    }
  end

  def parent_factory do
    school = insert(:school)

    %Videdal.Parent{
      id: Ecto.UUID.generate(),
      name: sequence(:parent_name, &"Parent #{&1}"),
      school_id: school.id
    }
  end

  def parent_student_factory do
    school = insert(:school)
    parent = insert(:parent, school_id: school.id)
    student = insert(:student, school_id: school.id)

    %Videdal.ParentStudent{
      id: Ecto.UUID.generate(),
      school_id: school.id,
      parent_id: parent.id,
      student_id: student.id
    }
  end

  def course_factory do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    %Videdal.Course{
      id: Ecto.UUID.generate(),
      title: sequence(:course_title, &"Course #{&1}"),
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0,
      school_id: school.id,
      teacher_id: teacher.id
    }
  end

  def enrollment_factory do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: insert(:teacher, school_id: school.id).id)

    %Videdal.Enrollment{
      id: Ecto.UUID.generate(),
      enrolled_on: Date.utc_today(),
      registration_status: "pending",
      school_id: school.id,
      student_id: student.id,
      course_id: course.id
    }
  end

  def grade_factory do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: insert(:teacher, school_id: school.id).id)

    %Videdal.Grade{
      id: Ecto.UUID.generate(),
      score: 10,
      school_id: school.id,
      student_id: student.id,
      course_id: course.id
    }
  end

  def announcement_factory do
    %Videdal.Announcement{
      id: Ecto.UUID.generate(),
      body: sequence(:announcement_body, &"Announcement #{&1}")
    }
  end
end
